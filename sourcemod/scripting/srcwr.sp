#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <convar_class>
#include <shavit>
#include <ripext> // https://github.com/ErikMinekus/sm-ripext

public Plugin myinfo = {
	name = "srcwr",
	author = "rtldg & pufftwitt & k3n",
	description = "Uploads run times & replays to a server for anyone to use.",
	version = "1.0",
	url = "https://github.com/rtldg/srcwr"
}

// TODO: Setup multi-replay system for trikz support...
// TODO: Tagteam support... multiple steamids & usernames...
	// probably implemented in another file that has player changes at ticks for the replay file...
// TODO: Determining/collapsing compatible zones...

Convar gCV_APIKey;
Convar gCV_APIUrl;
Convar gCV_ReplayUrl;
Convar gCV_Enabled;

ConVar hostname;
ConVar sv_maxvelocity;
ConVar sv_gravity;
ConVar sv_friction;
// CSGO convars
ConVar sv_staminajumpcost;
ConVar sv_staminalandcost;
ConVar sv_staminamax;
ConVar sv_ladder_scale_speed;

char gS_DataFolder[PLATFORM_MAX_PATH];

bool gB_Replay = false;

public void OnPluginStart()
{
	gCV_APIKey = new Convar("srcwr_api_key", "", "description", FCVAR_PROTECTED);
	gCV_APIUrl = new Convar("srcwr_api_url", "https://api.srcwr.com/v1/", "description", FCVAR_PROTECTED);
	gCV_ReplayUrl = new Convar("srcwr_replay_url", "https://storage.srcwr.com/v1/", "description", FCVAR_PROTECTED);
	gCV_Enabled = new Convar("srcwr_enabled", "3", "0 = upload nothing. 1 = upload every time. 2 = upload every time and WR replays. 3 = upload every time and every replay", 0, true, 0.0, true, 3.0);

	RegConsoleCmd("sm_srcwr", Command_SRCWR, "View global runs.");

	AutoExecConfig();

	hostname       = FindConVar("hostname");
	sv_maxvelocity = FindConVar("sv_maxvelocity");
	sv_gravity     = FindConVar("sv_gravity");
	sv_friction    = FindConVar("sv_friction");

	if (GetEngineVersion() == Engine_CSGO)
	{
		sv_staminajumpcost    = FindConVar("sv_staminajumpcost");
		sv_staminalandcost    = FindConVar("sv_staminalandcost");
		sv_staminamax         = FindConVar("sv_staminamax");
		sv_ladder_scale_speed = FindConVar("sv_ladder_scale_speed");
	}

	gB_Replay = LibraryExists("shavit-replay");

	BuildPath(Path_SM, gS_DataFolder, sizeof(gS_DataFolder), "/data/srcwr");
	if (!DirExists(gS_DataFolder))
		CreateDirectory(gS_DataFolder, 511);
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-replay"))
	{
		gB_Replay = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-replay"))
	{
		gB_Replay = false;
	}
}

bool ShouldSaveReplayCopy(bool iswr)
{
	if (gCV_Enabled.IntValue >= 2)
	{
		if (gCV_Enabled.IntValue >= 3 || iswr)
			return true;
	}
	return false;
}

public Action Shavit_ShouldSaveReplayCopy(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp, bool iswr, bool istoolong)
{
	if (ShouldSaveReplayCopy(iswr))
		return Plugin_Changed;
	return Plugin_Continue;
}

public void Shavit_OnFinish(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp)
{
	if (gCV_Enabled.IntValue < 1)
		return;

	// check for unranked

	JSONObject json = new JSONObject();

	char tmp[256];
	char mapname[PLATFORM_MAX_PATH];
	GetCurrentMap(mapname, sizeof(mapname));

	json.SetString("mapname", mapname);
	json.SetInt("steamAccountId", GetSteamAccountID(client, false));

	json.SetFloat("time", time);
	json.SetFloat("tickrate", 1.0 / GetTickInterval());

	hostname.GetString(tmp, sizeof(tmp));
	json.SetString("serverName", tmp);

	// TODO: Not needed? Just calc ticks as "time / GetTickInterval()"? Or just grab from replay file?
	/*
	if (gB_Replay)
	{
		json.SetInt("ticks", Shavit_GetClientFrameCount(client) - Shavit_GetPlayerTimerFrame(client));
		json.SetInt("preframes", Shavit_GetPlayerPreFrame(client));
		//json.SetInt("postframes", 0);
	}
	else
	{
		json.SetInt("ticks", RoundFloat(time / GetTickInterval()));
		json.SetInt("preframes", 0);
		//json.SetInt("postframes", 0);
	}
	*/

	json.SetInt("timestamp", timestamp);
	FormatTime(tmp, sizeof(tmp), "%z");
	json.SetString("timestampOffset", tmp);

	json.SetInt("jumps", jumps);
	json.SetInt("strafes", strafes);
	json.SetFloat("sync", sync);
	json.SetFloat("perfs", perfs);

	json.SetInt("server_track", track);
	json.SetInt("server_style", style);

	Shavit_GetStyleSetting(style, "name", tmp, sizeof(tmp));
	json.SetString("server_style_name", tmp);

	json.SetFloat("velocity_avg", avgvel);
	json.SetFloat("velocity_max", maxvel);
	json.SetInt("checkpointsUsed", Shavit_GetTimesTeleported(client));

	json.SetBool("autobhop", Shavit_GetStyleSettingBool(style, "autobhop"));
	json.SetBool("easybhop", Shavit_GetStyleSettingBool(style, "easybhop"));
	json.SetInt("prespeedSetting", Shavit_GetStyleSettingInt(style, "prespeed"));
	json.SetFloat("velocityLimit", Shavit_GetStyleSettingFloat(style, "velocity_limit"));
	json.SetBool("sv_enablebunnyhopping", Shavit_GetStyleSettingBool(style, "bunnyhopping"));
	json.SetFloat("sv_airaccelerate", Shavit_GetStyleSettingFloat(style, "airaccelerate"));
	json.SetFloat("runspeed", Shavit_GetStyleSettingFloat(style, "runspeed"));
	json.SetFloat("gravityMultiplier", Shavit_GetStyleSettingFloat(style, "gravity"));
	json.SetFloat("speedMultiplier", Shavit_GetStyleSettingFloat(style, "speed"));
	//json.SetBool("halftime", Shavit_GetStyleSettingBool(style, "halftime")); // sets timescale to 0.5
	json.SetFloat("timescale", Shavit_GetStyleSettingFloat(style, "timescale"));
	json.SetFloat("velocityPercent", Shavit_GetStyleSettingFloat(style, "velocity"));
	json.SetFloat("bonusVelocity", Shavit_GetStyleSettingFloat(style, "bonus_velocity"));
	json.SetFloat("minVelocity", Shavit_GetStyleSettingFloat(style, "min_velocity"));
	json.SetFloat("jumpMultiplier", Shavit_GetStyleSettingFloat(style, "jump_multiplier"));
	json.SetFloat("jumpBonus", Shavit_GetStyleSettingFloat(style, "jump_bonus"));
	json.SetBool("blockW", Shavit_GetStyleSettingBool(style, "block_w"));
	json.SetBool("blockA", Shavit_GetStyleSettingBool(style, "block_a"));
	json.SetBool("blockS", Shavit_GetStyleSettingBool(style, "block_s"));
	json.SetBool("blockD", Shavit_GetStyleSettingBool(style, "block_d"));
	json.SetBool("blockUse", Shavit_GetStyleSettingBool(style, "block_use"));
	json.SetInt("forceHSW", Shavit_GetStyleSettingInt(style, "force_hsw"));
	json.SetBool("forceKeysOnGround", Shavit_GetStyleSettingBool(style, "force_groundkeys"));
	json.SetInt("blockpleft", Shavit_GetStyleSettingInt(style, "block_pright"));     // TODO: turn into bool & json.SetFloat("pleftrightDelay")
	json.SetInt("blockpright", Shavit_GetStyleSettingInt(style, "block_pstrafe"));   // TODO: turn into bool & json.SetFloat("pleftrightDelay")
	//json.SetInt("blockpstrafe", ss.iBlockPStrafe); // TODO: ?
	json.SetBool("kzcheckpoints", Shavit_GetStyleSettingBool(style, "kzcheckpoints"));
	json.SetBool("strafeCountW", Shavit_GetStyleSettingBool(style, "strafe_count_w"));
	json.SetBool("strafeCountA", Shavit_GetStyleSettingBool(style, "strafe_count_a"));
	json.SetBool("strafeCountS", Shavit_GetStyleSettingBool(style, "strafe_count_s"));
	json.SetBool("strafeCountD", Shavit_GetStyleSettingBool(style, "strafe_count_d"));

	json.SetFloat("sv_maxvelocity", sv_maxvelocity.FloatValue);
	json.SetFloat("sv_gravity", sv_gravity.FloatValue);
	json.SetFloat("sv_friction", sv_friction.FloatValue);

	if (GetEngineVersion() == Engine_CSGO)
	{
		json.SetFloat("sv_staminajumpcost", sv_staminajumpcost.FloatValue);
		json.SetFloat("sv_staminalandcost", sv_staminalandcost.FloatValue);
		json.SetFloat("sv_staminamax", sv_staminamax.FloatValue);
		json.SetFloat("sv_ladder_scale_speed", sv_ladder_scale_speed.FloatValue);
	}

	// Plugin settings:
	//infiniteammo // sv_infinite_ammo in csgo
	//autofire for semi-auto weapons
	//noslide
	//boosterfix
	//rngfix
	//surffix

	char special[sizeof(stylestrings_t::sSpecialString)];
	Shavit_GetStyleStrings(style, sSpecialString, special, sizeof(special));

	json.SetBool("segments", StrContains(special, "segments") != -1);
	json.SetBool("tas", StrContains(special, "tas") != -1);

	if (StrContains(special, "unreal") != -1)
	{
		json.SetBool("unreal", true);
		// add power settings & gun configs or whatever
	}

	//delete json;
	char outPath[PLATFORM_MAX_PATH];
	FormatEx(outPath, sizeof(outPath), "%s/%d_%d_%s.json", gS_DataFolder, timestamp, GetSteamAccountID(client, false), mapname);
	json.ToFile(outPath);
}

public void Shavit_OnReplaySaved(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp, bool isWR, bool isTooLong, bool isCopy, const char[] path)
{
	PrintToChatAll("replay saved at %s", path);
}

Action Command_SRCWR(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: !srcwr <mapname>");
		return Plugin_Handled;
	}

	if (client == 0 || IsFakeClient(client))// || !IsClientAuthorized(client))
		return Plugin_Handled;

	char mapname[160];
	GetCmdArg(1, mapname, sizeof(mapname));

	return Plugin_Handled;
}
