#pragma semicolon 1

#include <sourcemod>
#include <tf2_stocks>

#define PL_VERSION "0.1"

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

//This mode based off on the Class Rescriptions Mod from Tsunami: http://forums.alliedmods.net/showthread.php?t=73104

public Plugin:myinfo =
{
	name        = "Class Warfare",
	author      = "Tsunami,JonathanFly",
	description = "Class Vs Class",
	version     = PL_VERSION,
	url         = "http://www.tsunami-productions.nl"
}

new g_iClass[MAXPLAYERS + 1];
new Handle:g_hEnabled;
new Handle:g_hFlags;
new Handle:g_hImmunity;
new Float:g_hLimits[4][10];
new String:g_sSounds[10][24] = {"", "vo/scout_no03.wav",   "vo/sniper_no04.wav", "vo/soldier_no01.wav",
																		"vo/demoman_no03.wav", "vo/medic_no03.wav",  "vo/heavy_no02.wav",
																		"vo/pyro_no01.wav",    "vo/spy_no02.wav",    "vo/engineer_no03.wav"};
                                                                        
static String:ClassNames[TFClassType][] = {"", "Scout", "Sniper", "Soldier", "Demoman", "Medic", "Heavy", "Pyro", "Spy", "Engineer" };
new blue_class;
new red_class;
new bool:switch_up_classes; 

public OnPluginStart()
{
	CreateConVar("sm_classrestrict_version", PL_VERSION, "Restrict classes in TF2.", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	g_hEnabled                                = CreateConVar("sm_classrestrict_enabled",       "1",  "Enable/disable restricting classes in TF2.");
	g_hFlags                                  = CreateConVar("sm_classrestrict_flags",         "",   "Admin flags for restricted classes in TF2.");
	g_hImmunity                               = CreateConVar("sm_classrestrict_immunity",      "0",  "Enable/disable admins being immune for restricted classes in TF2.");
     
	HookEvent("player_changeclass", Event_PlayerClass);
	HookEvent("player_spawn",       Event_PlayerSpawn);
	HookEvent("player_team",        Event_PlayerTeam);
    
    HookEvent("teamplay_round_active", Event_RoundActive);
    HookEvent("teamplay_setup_finished",Event_SetupFinished);
    
    HookEvent("teamplay_round_win",Event_RoundOver);
       
    //Going nuts, can't seem to get these random functions to seed!   
    new seed[4];
	seed[0] = GetTime();
	seed[1] = GetTime() / 42;
    seed[2] = GetTime() / 42;
	seed[3] = GetTime() / 137;

	for (new i = 0; i < 4; i++)
	{
		LogError("Seed[%i] = %i", i, seed[i]);
	}

	SetURandomSeed(seed, 4);


    for (new i = 0; i < 10; i++) {
    LogError("Random[%i] = %i", i, Math_GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER));
    }    
    LimitAllClasses();
        
    blue_class = Math_GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER);
    red_class = Math_GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER);
    
    g_hLimits[TF_TEAM_BLU][blue_class] = -1.0;
    g_hLimits[TF_TEAM_RED][red_class] = -1.0;
    
    switch_up_classes=false;
    
    
     
}
public Event_RoundOver(Handle:event, const String:name[], bool:dontBroadcast) {

   new WinnerTeam = GetEventInt(event, "team"); 
   new FullRound = GetEventInt(event, "full_round"); 
   new WinReason = GetEventInt(event, "winreason"); 
   new FlagCapLimit = GetEventInt(event, "flagcaplimit"); 
   
   //PrintToChatAll("Full Round? %d | WinnerTeam: %d | WinReason: %d | FlagCapLimit: %d", FullRound, WinnerTeam, WinReason, FlagCapLimit); 
 
        //if(FullRound == 1) //On Dustboal, each stage is a miniround.  Could probably only reset for full rounds...
        //{
            switch_up_classes=true;
        //}
        

}
public OnMapStart()
{
	decl i, String:sSound[32];
	for(i = 1; i < sizeof(g_sSounds); i++)
	{
		Format(sSound, sizeof(sSound), "sound/%s", g_sSounds[i]);
		PrecacheSound(g_sSounds[i]);
		AddFileToDownloadsTable(sSound);
	}
}

public OnClientPutInServer(client)
{
	g_iClass[client] = TF_CLASS_UNKNOWN;
}

public Event_PlayerClass(Handle:event, const String:name[], bool:dontBroadcast)
{
	new iClient = GetClientOfUserId(GetEventInt(event, "userid")),
			iClass  = GetEventInt(event, "class"),
			iTeam   = GetClientTeam(iClient);
	
	if(!(GetConVarBool(g_hImmunity) && IsImmune(iClient)) && IsFull(iTeam, iClass))
	{
		ShowVGUIPanel(iClient, iTeam == TF_TEAM_BLU ? "class_blue" : "class_red");
		EmitSoundToClient(iClient, g_sSounds[iClass]);
        TF2_SetPlayerClass(iClient, TFClassType:g_iClass[iClient]);
        TF2_RegeneratePlayer(iClient);
        PrintCenterText(iClient, "%s%s%s%s%s", ClassNames[iClass],  " Is Not An Option This Round! It's Red ", ClassNames[red_class], " vs Blue ", ClassNames[blue_class] );      
	}
}


public Action:Event_RoundActive(Handle:event, const String:name[], bool:dontBroadcast)
{
    //When the round is active and players can move
    //If no setup time is found then game continues as usual
    new m_nSetupTimeLength = FindSendPropOffs("CTeamRoundTimer", "m_nSetupTimeLength");    
    new i = -1;
    new team_round_timer = FindEntityByClassname(i, "team_round_timer");
    if (IsValidEntity(team_round_timer))
    {
        new setupTime = GetEntData(team_round_timer,m_nSetupTimeLength);
        
        if(setupTime > 0)
        {
        
        
            if (switch_up_classes) {
    
                LimitAllClasses();
                
                blue_class = Math_GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER);
                red_class = Math_GetRandomInt(TF_CLASS_SCOUT, TF_CLASS_ENGINEER);
                
                g_hLimits[TF_TEAM_BLU][blue_class] = -1.0;
                g_hLimits[TF_TEAM_RED][red_class] = -1.0;
                
                PrintCenterTextAll("%s%s%s%s", "New Round of Class Warfare! Red ", ClassNames[red_class], " vs Blue ", ClassNames[blue_class] ); 
                PrintToChatAll("%s%s%s%s", "New Round of Class Warfare! Red ", ClassNames[red_class], " vs Blue ", ClassNames[blue_class] );
                switch_up_classes=false;               
                } else {
                PrintCenterTextAll("%s%s%s%s", "Welcome to Class Warfare! Red ", ClassNames[red_class], " vs Blue ", ClassNames[blue_class] );
                PrintToChatAll("%s%s%s%s", "Welcome to Class Warfare! Red ", ClassNames[red_class], " vs Blue ", ClassNames[blue_class] );             
                }    
                  		
        }
    }
    ChangeBotClasses();
} 

public Action:Event_SetupFinished(Handle:event,  const String:name[], bool:dontBroadcast) 
{
    switch_up_classes = false;
    ChangeBotClasses();
    
    PrintCenterTextAll("%s%s%s%s", "Class Warfare Begins! Red ", ClassNames[red_class], " vs Blue ", ClassNames[blue_class] );
    PrintToChatAll("%s%s%s%s", "Class Warfare Begins! ", ClassNames[red_class], " vs Blue ", ClassNames[blue_class] );
}  



public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new iClient = GetClientOfUserId(GetEventInt(event, "userid")),
			iTeam   = GetClientTeam(iClient);
	
        
	if(!(GetConVarBool(g_hImmunity) && IsImmune(iClient)) && IsFull(iTeam, (g_iClass[iClient] = _:TF2_GetPlayerClass(iClient))))
	{
     
		ShowVGUIPanel(iClient, iTeam == TF_TEAM_BLU ? "class_blue" : "class_red");
		EmitSoundToClient(iClient, g_sSounds[g_iClass[iClient]]);
              
		PickClass(iClient);
        TF2_RegeneratePlayer(iClient);
	}
}

public Event_PlayerTeam(Handle:event,  const String:name[], bool:dontBroadcast)
{
	new iClient = GetClientOfUserId(GetEventInt(event, "userid")),
			iTeam   = GetEventInt(event, "team");
	
	if(!(GetConVarBool(g_hImmunity) && IsImmune(iClient)) && IsFull(iTeam, g_iClass[iClient]))
	{
		ShowVGUIPanel(iClient, iTeam == TF_TEAM_BLU ? "class_blue" : "class_red");
		EmitSoundToClient(iClient, g_sSounds[g_iClass[iClient]]);
		PickClass(iClient);
	}
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

bool:IsImmune(iClient)
{
	if(!iClient || !IsClientInGame(iClient))
		return false;
	
	decl String:sFlags[32];
	GetConVarString(g_hFlags, sFlags, sizeof(sFlags));
	
	// If flags are specified and client has generic or root flag, client is immune
	return !StrEqual(sFlags, "") && GetUserFlagBits(iClient) & (ReadFlagString(sFlags)|ADMFLAG_ROOT);
}

ChangeBotClasses() {
    //Manually force the bots to the classes               
    for (new i = 1; i <= MaxClients; ++i) {            

        if (IsClientConnected(i) && IsFakeClient(i)) {
            PickClass(i);
            TF2_RegeneratePlayer(i);            
        }
   }
}

LimitAllClasses() {
    for(new i = TF_CLASS_SCOUT; i <= TF_CLASS_ENGINEER; i++)
    {
        g_hLimits[TF_TEAM_BLU][i] = 0.0;
        g_hLimits[TF_TEAM_RED][i] = 0.0;
    }
}

PickClass(iClient)
{
	// Loop through all classes, starting at random class
	for(new i = (TF_CLASS_SCOUT, TF_CLASS_ENGINEER), iClass = i, iTeam = GetClientTeam(iClient);;)
	{
		// If team's class is not full, set client's class
		if(!IsFull(iTeam, i))
		{
			TF2_SetPlayerClass(iClient, TFClassType:i);
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
}

stock Math_GetRandomInt(min, max)
{
	new random = GetURandomInt();
	
	if (random == 0) {
		random++;
	}

	return RoundToCeil(float(random) / (float(SIZE_OF_INT) / float(max - min + 1))) + min - 1;
}