#pragma semicolon 1

#include <sourcemod>
#include <tf2_stocks>

#define PL_VERSION "0.2"

#define TF_CLASS_DEMOMAN		4
#define TF_CLASS_ENGINEER		9
#define TF_CLASS_HEAVY			6
#define TF_CLASS_MEDIC			5
#define TF_CLASS_PYRO				7
#define TF_CLASS_SCOUT			1
#define TF_CLASS_SNIPER			2
#define TF_CLASS_SOLDIER		3
#define TF_CLASS_SPY				8
#define TF_CLASS_UNKNOWN		0

#define TF_TEAM_BLU					3
#define TF_TEAM_RED					2

#define SIZE_OF_INT		2147483647		// without 0

//This code is based on the Class Restrictions Mod from Tsunami: http://forums.alliedmods.net/showthread.php?t=73104

public Plugin:myinfo =
{
    name        = "Class Warfare",
    author      = "Tsunami,JonathanFlynn",
    description = "Class Vs Class",
    version     = PL_VERSION,
    url         = "https://github.com/JonathanFlynn/Class-Warfare"
}

new g_iClass[MAXPLAYERS + 1];
new Handle:g_hEnabled;
new Handle:g_hFlags;
new Handle:g_hImmunity;
new Handle:g_hClassVoteMenu 		= INVALID_HANDLE;
//new Handle:g_hClassChangeInterval;
new Float:g_hLimits[4][10];
new String:g_sSounds[10][24] = {"", "vo/scout_no03.wav",   "vo/sniper_no04.wav", "vo/soldier_no01.wav",
    "vo/demoman_no03.wav", "vo/medic_no03.wav",  "vo/heavy_no02.wav",
    "vo/pyro_no01.wav",    "vo/spy_no02.wav",    "vo/engineer_no03.wav"};

static String:ClassNames[TFClassType][] = {"", "Scout", "Sniper", "Soldier", "Demoman", "Medic", "Heavy", "Pyro", "Spy", "Engineer" };

enum e_PlayerInfo
{
    iBalanceTime,
bool:bHasVoted,
    iBlockTime,
    iBlockWarnings,
    iTeamPreference,
    iTeamworkTime,
bool:bIsVoteAdmin,
    iBuddy,
    iFrags,
    iDeaths,
bool:bHasFlag,
    iSpecChangeTime,
    iGameMe_Rank,
    iGameMe_Skill,
    iGameMe_gRank,
    iGameMe_gSkill,
    iGameMe_SkillChange,
    iHlxCe_Rank,
    iHlxCe_Skill,
};
new g_aPlayers[MAXPLAYERS + 1][e_PlayerInfo];
new Handle:g_hVoteDelayTimer 		= INVALID_HANDLE;
new bool:g_bVoteAllowed = true;

new g_iBlueClass1;
new g_iRedClass1;

new g_iBlueClass2;
new g_iRedClass2;



new RandomizedThisRound = 0;

public OnPluginStart()
{
    CreateConVar("sm_classwarfare_version", PL_VERSION, "Class Warfare in TF2.", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
    
    g_hEnabled                                = CreateConVar("sm_classwarfare_enabled",       "1",  "Enable/disable the Class Warfare mod in TF2.");
    g_hFlags                                  = CreateConVar("sm_classwarfare_flags",         "",   "Admin flags for restricted classes in TF2.");
    g_hImmunity                               = CreateConVar("sm_classwarfare_immunity",      "0",  "Enable/disable admins being immune for restricted classes in TF2.");
    //g_hClassChangeInterval                        = CreateConVar("sm_classwarfare_change_interval",   "0",  "Shuffle the classes every x minutes, 0 for round only");

    HookEvent("player_changeclass", Event_PlayerClass);
    HookEvent("player_spawn",       Event_PlayerSpawn);
    HookEvent("player_team",        Event_PlayerTeam);
    
    HookEvent("teamplay_round_start", Event_RoundStart);
    HookEvent("teamplay_setup_finished",Event_SetupFinished);
    
    HookEvent("teamplay_round_win",Event_RoundOver);
    
    RegConsoleCmd("say", Command_Say);
    
    new seeds[1];
    seeds[0] = GetTime();
    SetURandomSeed(seeds, 1);

    // for (new i = 0; i < 10; i++) {
    // LogError("Random[%i] = %i", i, Math_GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER));
    // }  
    
    decl i, String:sSound[32];
    for(i = 1; i < sizeof(g_sSounds); i++)
    {
        Format(sSound, sizeof(sSound), "sound/%s", g_sSounds[i]);
        PrecacheSound(g_sSounds[i]);
        AddFileToDownloadsTable(sSound);
    }
    
    SetupClassRestrictions();
    
}

public Action:Command_Say(client, args)
{
    if (!client)
    {
        return Plugin_Continue;
    }

    decl String:text[192];
    if (!GetCmdArgString(text, sizeof(text)))
    {
        return Plugin_Continue;
    }
    
    new startidx = 0;
    if(text[strlen(text)-1] == '"')
    {
        text[strlen(text)-1] = '\0';
        startidx = 1;
    }

    if (strcmp(text[startidx], "nextclass", false) == 0)
    {
        if (!g_bVoteAllowed)
        {
            ReplyToCommand(client, "\x01\x04[SM]\x01 %s", "You must wait before voting again.");
        }	else {
            StartClassVote();
        } 
    }
    
    return Plugin_Continue;	
}

StartClassVote(time=30)
{
    if (IsVoteInProgress())
    {
        PrintToChatAll("\x01\x04[SM]\x01 %s", "VoteWillStart");
        return;
    } 
    
    DelayPublicVoteTriggering();
    g_hClassVoteMenu = CreateMenu(Handler_VoteCallback, MenuAction:MENU_ACTIONS_ALL);
    
    new String:sTmpTitle[64];
    Format(sTmpTitle, 64, "Randomize Classes Again?");
    
    SetMenuTitle(g_hClassVoteMenu, sTmpTitle);
    AddMenuItem(g_hClassVoteMenu, "1", "Yes");
    AddMenuItem(g_hClassVoteMenu, "2", "No");
    SetMenuExitButton(g_hClassVoteMenu, false);
    VoteMenuToAll(g_hClassVoteMenu, time);
}


public Handler_VoteCallback(Handle:menu, MenuAction:action, param1, param2)
{
    DelayPublicVoteTriggering();
    if (action == MenuAction_End)
    {
        CloseHandle(menu);
    } else if (action == MenuAction_VoteEnd) {
        /* 0=yes, 1=no */
        if (param1 == 1)
        {
            PrintCenterTextAll("%s", "Vote Failed, keeping current matchup." );
            PrintToChatAll("%s", "Vote Failed, keeping current matchup." ); 
             
        }
        else {
            SetupClassRestrictions();
            AssignBotClasses(); //Let players keep the current class until they die
            PrintCenterTextAll("%s", "Vote Passed." );
            PrintToChatAll("%s", "Vote Passed."  ); 
            PrintStatus();
        }
    }

}

DelayPublicVoteTriggering(bool:success = false)  // success means a vote happened... longer delay
{
    for (new i = 0; i <= MaxClients; i++)	
    g_aPlayers[i][bHasVoted] = false;
    
    g_bVoteAllowed = false;
    if (g_hVoteDelayTimer != INVALID_HANDLE)
    {
        KillTimer(g_hVoteDelayTimer);
        g_hVoteDelayTimer = INVALID_HANDLE;
    }
    new Float:fDelay = 60.0;
    if (success) {
        fDelay = fDelay * 2.0;
    }
    g_hVoteDelayTimer = CreateTimer(fDelay, TimerEnable, TIMER_FLAG_NO_MAPCHANGE);
}

public Action:TimerEnable(Handle:timer)
{
    g_bVoteAllowed = true;
    g_hVoteDelayTimer = INVALID_HANDLE;
    return Plugin_Handled;
}

public Event_RoundOver(Handle:event, const String:name[], bool:dontBroadcast) {

    //new WinnerTeam = GetEventInt(event, "team"); 
    new FullRound = GetEventInt(event, "full_round"); 
    //new WinReason = GetEventInt(event, "winreason"); 
    //new FlagCapLimit = GetEventInt(event, "flagcaplimit"); 

    //PrintToChatAll("Full Round? %d | WinnerTeam: %d | WinReason: %d | FlagCapLimit: %d", FullRound, WinnerTeam, WinReason, FlagCapLimit); 
    
    //On Dustbowl, each stage is a mini-round.  If we switch up between minirounds,
    //the teams may end up in a stalemate with lots of times on the clock... 
    
    if(FullRound == 1) 
    {
        RandomizedThisRound = 0;
    }
}

public OnClientPutInServer(client)
{
    g_iClass[client] = TF_CLASS_UNKNOWN;
}

public Event_PlayerClass(Handle:event, const String:name[], bool:dontBroadcast)
{
    if(!GetConVarBool(g_hEnabled))
    return;
    
    new iClient = GetClientOfUserId(GetEventInt(event, "userid")),
    iClass  = GetEventInt(event, "class");
    
    if(!IsValidClass(iClient, iClass))
    {
        new iTeam   = GetClientTeam(iClient);
        //ShowVGUIPanel(iClient, iTeam == TF_TEAM_BLU ? "class_blue" : "class_red"); 
        //EmitSoundToClient(iClient, g_sSounds[iClass]);
        //TF2_SetPlayerClass(iClient, TFClassType:g_iClass[iClient]);
        
        if (iTeam == TF_TEAM_BLU) {        
        PrintCenterText(iClient, "%s%s%s%s%s", ClassNames[iClass],  " Is Not An Option This Round! You must pick ", ClassNames[g_iBlueClass1], " or ", ClassNames[g_iBlueClass2] );   
        PrintToChat(iClient, "%s%s%s%s%s", ClassNames[iClass],  " Is Not An Option This Round! You must pick ", ClassNames[g_iBlueClass1], " or ", ClassNames[g_iBlueClass2]);
        }
        else {
        PrintCenterText(iClient, "%s%s%s%s%s", ClassNames[iClass],  " Is Not An Option This Round! You must pick ", ClassNames[g_iRedClass1], " or ", ClassNames[g_iRedClass2] );   
        PrintToChat(iClient, "%s%s%s%s%s", ClassNames[iClass],  " Is Not An Option This Round! You must pick ", ClassNames[g_iRedClass1], " or ", ClassNames[g_iRedClass1]);
        }

        AssignValidClass(iClient);
    }    
}


public Action:Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
    PrintToChatAll("%s", "Regular Round Start Event");
    RoundClassRestrictions();
    PrintStatus();
} 

public Action:Event_SetupFinished(Handle:event,  const String:name[], bool:dontBroadcast) 
{   
    PrintStatus();
}  

public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
    new iClient = GetClientOfUserId(GetEventInt(event, "userid"));  
    g_iClass[iClient] = _:TF2_GetPlayerClass(iClient);
    
    if(!IsValidClass(iClient,g_iClass[iClient]))
    {   //new iTeam   = GetClientTeam(iClient);       
        //ShowVGUIPanel(iClient, iTeam == TF_TEAM_BLU ? "class_blue" : "class_red");
        //EmitSoundToClient(iClient, g_sSounds[g_iClass[iClient]]);
        
        AssignValidClass(iClient);
    }
}

public Event_PlayerTeam(Handle:event,  const String:name[], bool:dontBroadcast)
{   
    new iClient = GetClientOfUserId(GetEventInt(event, "userid"));
    
    if(!IsValidClass(iClient,g_iClass[iClient]))
    {
        //new iTeam   = GetClientTeam(iClient);
        //ShowVGUIPanel(iClient, iTeam == TF_TEAM_BLU ? "class_blue" : "class_red");
        //EmitSoundToClient(iClient, g_sSounds[g_iClass[iClient]]);
        AssignValidClass(iClient);
    }
}

bool:IsValidClass(iClient, iClass) {

    new iTeam = GetClientTeam(iClient);
    
    if(!(GetConVarBool(g_hImmunity) && IsImmune(iClient)) && IsFull(iTeam, iClass)) {
        return false;
    }
    return true;   
}

bool:IsFull(iTeam, iClass)
{
    // If plugin is disabled, or team or class is invalid, class is not full
    if(!GetConVarBool(g_hEnabled) || iTeam < TF_TEAM_RED || iClass < TF_CLASS_SCOUT)
    return false;
    
    // Get team's class limit
    new iLimit,
Float:flLimit = g_hLimits[iTeam][iClass];
    
    // If limit is a percentage, calculate real limit
    if(flLimit > 0.0 && flLimit < 1.0)
    iLimit = RoundToNearest(flLimit * GetTeamClientCount(iTeam));
    else
    iLimit = RoundToNearest(flLimit);
    
    // If limit is -1, class is not full
    if(iLimit == -1)
    return false;
    // If limit is 0, class is full
    else if(iLimit == 0)
    return true;
    
    // Loop through all clients
    for(new i = 1, iCount = 0; i <= MaxClients; i++)
    {
        // If client is in game, on this team, has this class and limit has been reached, class is full
        if(IsClientInGame(i) && GetClientTeam(i) == iTeam && _:TF2_GetPlayerClass(i) == iClass && ++iCount > iLimit)
        return true;
    }
    
    return false;
}

PrintStatus() {
    if(!GetConVarBool(g_hEnabled))
    return;
    
    PrintCenterTextAll("%s%s%s%s%s%s%s%s", "This is Class Warfare: Red ", ClassNames[g_iRedClass1], " and ", ClassNames[g_iRedClass2], " vs Blue ", ClassNames[g_iBlueClass1], " and ", ClassNames[g_iBlueClass2] );
    PrintToChatAll("%s%s%s%s%s%s%s%s", "This is Class Warfare: Red ", ClassNames[g_iRedClass1], " and ", ClassNames[g_iRedClass2], " vs Blue ", ClassNames[g_iBlueClass1], " and ", ClassNames[g_iBlueClass2] );
}
bool:IsImmune(iClient)
{
    if(!iClient || !IsClientInGame(iClient))
    return false;
    
    decl String:sFlags[32];
    GetConVarString(g_hFlags, sFlags, sizeof(sFlags));
    
    // If flags are specified and client has generic or root flag, client is immune
    return !StrEqual(sFlags, "") && GetUserFlagBits(iClient) & (ReadFlagString(sFlags)|ADMFLAG_ROOT);
}

AssignPlayerClasses() {
    for (new i = 1; i <= MaxClients; ++i) {            
        if (IsClientConnected(i) && (!IsValidClass(i,g_iClass[i]))) {
            AssignValidClass(i);     
        }
    }
}

AssignBotClasses() {
    for (new i = 1; i <= MaxClients; ++i) {            
        if (IsClientConnected(i) && (!IsValidClass(i,g_iClass[i])) && IsFakeClient(i)) {
            AssignValidClass(i);     
            TF2_RespawnPlayer(i); //If bots don't respawn, they seem to get stuck sometimes?
        }
    }
}

// Run once per real round (event fires multiple times)
RoundClassRestrictions() {
    if ( RandomizedThisRound == 0) {
        SetupClassRestrictions();
    } 
    RandomizedThisRound = 1;
    AssignPlayerClasses();
}

SetupClassRestrictions() {
    
    for(new i = TF_CLASS_SCOUT; i <= TF_CLASS_ENGINEER; i++)
    {
        g_hLimits[TF_TEAM_BLU][i] = 0.0;
        g_hLimits[TF_TEAM_RED][i] = 0.0;
    }
    
 
    g_iBlueClass1 = Math_GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER);
    g_iRedClass1 = Math_GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER);
    
    g_iBlueClass2 = Math_GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER);
    g_iRedClass2 = Math_GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER);
    
    g_hLimits[TF_TEAM_BLU][g_iBlueClass1] = -1.0;
    g_hLimits[TF_TEAM_RED][g_iRedClass1] = -1.0; 
    
    g_hLimits[TF_TEAM_BLU][g_iBlueClass2] = -1.0;
    g_hLimits[TF_TEAM_RED][g_iRedClass2] = -1.0; 

    // new seconds = GetConVarInt(g_hClassChangeInterval) * 60;
    // if (seconds > 0) { 
        // CreateTimer(float(seconds), TimerClassChange);
    // }
    
    //rewrite this later
    if ((g_iBlueClass1 == g_iBlueClass2) || (g_iRedClass1 == g_iRedClass2)) {
    SetupClassRestrictions();
    }
    
}

public Action:TimerClassChange(Handle:timer, any:client)
{
    SetupClassRestrictions();
    PrintToChatAll("%s%s%s%s%s%s%s%s", "Mid Round Class Change:Red ", ClassNames[g_iRedClass1], " and ", ClassNames[g_iRedClass2], " vs Blue ", ClassNames[g_iBlueClass1], " and ", ClassNames[g_iBlueClass1] );
}

/* AssignValidClass(iClient)
{
    // Loop through all classes, starting at random class
    for(new i = (TF_CLASS_SCOUT, TF_CLASS_ENGINEER), iClass = i, iTeam = GetClientTeam(iClient);;)
    {
        // If team's class is not full, set client's class
        if(!IsFull(iTeam, i))
        {
            TF2_SetPlayerClass(iClient, TFClassType:i);
            TF2_RegeneratePlayer(iClient);  
            if (!IsPlayerAlive(iClient)) {
                TF2_RespawnPlayer(iClient);
            }
            g_iClass[iClient] = i;
            break;
        }
        // If next class index is invalid, start at first class
        else if(++i > TF_CLASS_ENGINEER)
        i = TF_CLASS_SCOUT;
        // If loop has finished, stop searching
        else if(i == iClass)
        break;
    }
} */

AssignValidClass(iClient)
{
    
    new i = Math_GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER);
    new iTeam = GetClientTeam(iClient);
    
    while (IsFull(iTeam, i)) {
    i = Math_GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER);
    }
    g_iClass[iClient] = i;
    
    TF2_SetPlayerClass(iClient, TFClassType:i);
    TF2_RegeneratePlayer(iClient);  
    if (!IsPlayerAlive(iClient)) {
        TF2_RespawnPlayer(iClient);
    }
  
}


stock Math_GetRandomInt(min, max)
{
    new random = GetURandomInt();
    
    if (random == 0) {
        random++;
    }

    return RoundToCeil(float(random) / (float(SIZE_OF_INT) / float(max - min + 1))) + min - 1;
}