/*=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
#											#
#			FS races v1.1 by Flovv			#
#											#
#			   Filterscript for				#
#				automated Races				#
=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=*/

#include <a_samp>
#include <streamer>
#include <sscanf2>




//needed plugins, Streamer Plugin by Incognito, sscanf2 by Y_Less



//********************************************************************
/////////////////////////////// SETTINGS /////////////////////////////
//********************************************************************

//use this to increase performance if your server has less than 500 slots or change it if your server has more than 500 slots
#undef MAX_PLAYERS
#define MAX_PLAYERS 20		//set to your max number of players


//set the maximum number of races to be loaded
#define MAX_RACES 50		//max number of races
#define MAX_CPS 201		//max number of checkpoints in a race


//use this function for whatever method you use to determine if a player is admin (just make sure to return true if player is admin or false if not)
PlayerIsAdmin(playerid)
{
	if(IsPlayerAdmin(playerid) == 1) return true;
	else return false;
}

//******************************************************************
////////////////////////// SETTINGS END ////////////////////////////
//******************************************************************






#define dcmd(%1,%2,%3) if (!strcmp((%3)[1], #%1, true, (%2)) && ((((%3)[(%2) + 1] == '\0') && (dcmd_%1(playerid, ""))) || (((%3)[(%2) + 1] == ' ') && (dcmd_%1(playerid, (%3)[(%2) + 2]))))) return 1

//functions that have to be forwarded for use in timers
forward Countdown(delay);
forward HideCountdown();
forward HideRaceStartedMsg();
forward HidePlayerFinishMsg(playerid);
forward HideWinMsg(playerid);
forward ShowPlayerFinishMsgDelayed(playerid);
forward GetBack(playerid);
forward AutoStart1();
forward AutoStart2();
forward AutoEnd1();
forward AutoEnd2();
forward HideTimeRemaining();

//OnPlayerExitVehicleEx vars
new playerveh[MAX_VEHICLES];		//save the playerid for every vehicle
new vehplayer[MAX_PLAYERS];			//save the vehicleid for player

//general
new autotimer[8];									//[0]autostart on(1) off(0), [1]timerid, [2]time(min), [3]join timerid, [4]join time(min), [5]counter, [6]autoend time, [7]autoend timerid
new rettime = 15;									//time to get back to vehicle
new exittimer[MAX_PLAYERS];							//timer id for timer that starts when player leaves vehicle
new exitcounter[MAX_PLAYERS] = 0;
new timer;											//countdown timer id
new count = 0;										//counter for Countdown
new scount = 5;										//start countdown time(sec)
new drace = 0;										//race to be deleted
new spawnarea;										//id of the race spawn area
new bool:freeze;									//freeze var for race start-freeze
new bool:sfreeze = true;							//start freeze on/off
new bool:winmsg;									//is the race winner msg shown atm?
new bool:noveh[MAX_PLAYERS];						//player is in race without vehicle
new bool:cprepair = false;							//repair veh every cp?
new Float:playerkoords[MAX_PLAYERS * 2][3];			//saving playerkoords
new weapons[MAX_PLAYERS][13][2];					//saving weapons
new Text:textdraws[MAX_PLAYERS+1][5];				//textdraws [pid][0]race position, [pid][1]race cp, [m_pl][0]raceinfo 1, [m_pl][1]raceinfo 2, [m_pl][2]race started msg line1, [m_]pl[3]line2, [m_pl][4]line3

//race vars
new race_editor[5];		//editor vars [0]->cp id, [1]->(0)editor free,(1) editor in use, [2]->checkpoint counter, [3]->playerid of the player using the editor, [4]->(0)cp placing disabled, (1)cp placing spawn, (2)cp placing race cps
new race_count = 0;		//race counter
new race[MAX_PLAYERS+1][3];			//race values
/*
[playerid][0] -> cp id
[playerid][1] -> passed cp
[playerid][2] -> player joined race
[MAX_PLAYERS][0] -> joins
[MAX_PLAYERS][1] -> race initialized
[MAX_PLAYERS][2] -> race started
*/
new rid = 0; //raceid
new rname[MAX_RACES + 1][64];		//race name
new rfilename[MAX_RACES + 1][64];	//race filename
new Float:rcp[MAX_RACES + 1][MAX_CPS + 1][5]; /*
rcp[raceID][checkpoint][vars]

[rid][checkpoint][0] -> x-koord (float)
[rid][checkpoint][1] -> y-koord (float)
[rid][checkpoint][2] -> z-koord (float)
[rid][checkpoint][3] -> how many players passed this cp (floatround)
[rid][checkpoint][4] -> parameters

[rid][0][4] -> cp diameter (float)
[rid][1][4] -> cp type (floatround)
[rid][2][4] -> number of cps (floatround)
[rid][3][4] -> world id (floatround)
[rid][4][4] -> max participants (floatround)
[rid][5][4] -> needed vehicle(0=no vehicle needed; 1=land vehicle; 2=car; 3=motorbike; 4=truck; 5=plane; 6=helicopter; 7=boat; 8=bike) (floatround)
[rid][6][4] -> future functions(unused atm)
[rid][7][4] -> future functions(unused atm)
[rid][8][4] -> future functions(unused atm)
[rid][9][4] -> future functions(unused atm)
[rid][MAX_CPS][0] -> enter spawn X (float)
[rid][MAX_CPS][1] -> enter spawn Y (float)
[rid][MAX_CPS][2] -> enter spawn Z (float)
[MAX_RACES][][]....-> Race Editor
*/
new rmapicons[MAX_PLAYERS];		//display mapicons for next cp, just in case the cp is to far away to be shown on minimap

public OnFilterScriptInit()
{
	LoadRaces();
	InitTextdraws();
	race_editor[3] = -1;
	//initialize race autostart default values
	autotimer[2] = 30;
	autotimer[4] = 5;
	autotimer[6] = 15;
	return 1;
	
}

public OnFilterScriptExit()
{
	DestroyTextdraws();
	return 1;
}

//*************************************************************
//************************ commands ***************************
//*************************************************************

public OnPlayerCommandText(playerid, cmdtext[])
{
	if(PlayerIsAdmin(playerid))
	{
		dcmd(start, 5, cmdtext);			//start race
		dcmd(end, 3,  cmdtext);				//end race
		dcmd(reload, 6, cmdtext);			//reload races
	}
	dcmd(race, 4, cmdtext);				//enter race
	dcmd(exit, 4, cmdtext);					//exit race
	return 0;
}

dcmd_start(playerid, params[])		//start race
{
	new sel[32];
	if(sscanf(params, "s[32]", sel))		//start race
	{
		SendClientMessage(playerid, 0xFF0000FF, "SERVER: /start race ?");
	}
	else if(!strcmp(sel, "race", true))		//initialize race
	{
		if(autotimer[0] == 1) return SendClientMessage(playerid, 0xFF0000FF, "ERRORE: Non puoi perche' l'autostart e' attivo");
		if(race[MAX_PLAYERS][1]==1)
		{
			race[MAX_PLAYERS][1]=0;		//set race status from "initilized"
			race[MAX_PLAYERS][2]=1;		//to "running"
			CreateFirstCP();
			timer = SetTimerEx("Countdown", 1000, true, "i", scount);
		}
		else if(race[MAX_PLAYERS][2]==1) SendClientMessage(playerid, 0xFF0000FF, "SERVER: Gara gia' iniziata.");
		else
		{
			if(race_count == 0) SendClientMessage(playerid, 0xFF0000FF, "SERVER: Nessuna gara trovata!");
			else
			{
				new race_sel[MAX_RACES * 64];		//63 char limitation to race name
				new race_ins[64];
				for(new i = 0; i < race_count; i++)		//read race names and creat race selection dialog
				{
					format(race_ins, sizeof(race_ins), "%s\r\n",rname[i]);
					strins(race_sel, race_ins, strlen(race_sel));
				}
				ShowPlayerDialog(playerid,2201,DIALOG_STYLE_LIST,"Seleziona",race_sel,"Inizia", "Annulla");
			}
		}
	}
	return 1;
}

dcmd_reload(playerid,params[])
{
	new sel[32];
	if(sscanf(params, "s[32]", sel))
	{
		SendClientMessage(playerid, 0xFF0000FF, "SERVER: /reload races ?");
	}
	else if(!strcmp(sel, "races"))
	{
		if(LoadRaces() != 1)
		{
			SendClientMessage(playerid, 0xFF0000FF, "SERVER: Errore nel caricamento delle gare.");
		}
		else SendClientMessage(playerid, 0xFF0000FF, "SERVER: Caricamento completato.");
	}
	return 1;
}

dcmd_end(playerid,params[])		//cancel race
{
	new par[64];
	if(sscanf(params, "s[64]", par))
	{
		if(race_editor[1] == 1) SendClientMessage(playerid, 0xFF0000FF, "SERVER: Editor in uso.");
		if(race[MAX_PLAYERS][1] + race[MAX_PLAYERS][2] != 0) SendClientMessage(playerid, 0xFF0000FF, "SERVER: Gara in corso. Usa /end per terminarla");
	}
	else if(!strcmp(par, "redit"))
	{
		if(race_editor[1] == 1) 
		{
			RaceEditorClose(playerid);
			SendClientMessage(playerid, 0xFF0000FF, "SERVER: Editor chiuso.");
		}
		else SendClientMessage(playerid, 0xFF0000FF, "ERRORE: Editor non aperto");
	}
	else if(!strcmp(par, "race"))
	{
		if(race[MAX_PLAYERS][1] + race[MAX_PLAYERS][2] != 0)
		{
			if(autotimer[0] == 1) return SendClientMessage(playerid, 0xFF0000FF, "ERRORE: Non puoi perche' l'autostart e' attivo");
			for (new i = 0; i < MAX_PLAYERS; i++)
			{
				if(race[i][2] == 1)		//kick players out of race
				{
					SetKoords(i);
					noveh[i] = false;
					RemovePlayerMapIcon(i, rmapicons[i]);
					SendClientMessage(i, 0xFF0000FF, "SERVER: La gara e' stata terminata!");
				}
			}
			EndRace();
			SendClientMessage(playerid, 0xFF0000FF, "SERVER: La gara e' stata terminata!");
		}
		else SendClientMessage(playerid, 0xFF0000FF, "ERRORE: Nessuna gara in corso.");
	}
	return 1;
}

dcmd_race(playerid, params[])		//join race
{
	new par[64];
	if(sscanf(params, "s[64]", par))
	{
		EnterRace(playerid);
	}
	else if(!strcmp(par, "editor"))		//start editor
	{
		if(race_editor[1] == 0)
		{
			race_editor[1] = 1;
			race_editor[3] = playerid;
			RaceEditor1(playerid);
		}
		else SendClientMessage(playerid, 0xFF0000, "SERVER: Editor gia' in uso.");
	}
	else if(!strcmp(par, "settings") && PlayerIsAdmin(playerid))
	{
		RaceSettings(playerid);
	}
	else if(PlayerIsAdmin(playerid)) SendClientMessage(playerid, 0xFF0000FF, "SERVER: Usa /race settings per modificare le impostazioni");
	else SendClientMessage(playerid, 0xFF0000FF, "Questo comando non ha parametri.");
	return 1;
}

dcmd_exit(playerid, params[])		//exit race
{
	if(!strcmp(params, ""))
	{
		if(race[playerid][2] == 1) ExitRace(playerid);
		else SendClientMessage(playerid, 0xFF0000FF, "SERVER: Non stai partecipando a nessuna gara.");
	}
	else
	{
		SendClientMessage(playerid, 0xFF0000FF, "Questo comando non ha parametri.");
	}
	return 1;
}

//************************************************************
//*********************** dialogs ****************************
//************************************************************

public OnDialogResponse(playerid, dialogid, response, listitem, inputtext[])
{
	switch(dialogid) // dialogid
	{
		case 2201:		// initialize race
		{
			if(!response) return 1; // cancel

			rid = listitem;		//set race ID
			race[MAX_PLAYERS][1] = 1;	//race initialized
			ShowRaceStartedMsg(10);
			race[MAX_PLAYERS][0] = 0;
			spawnarea = CreateDynamicCircle(rcp[rid][MAX_CPS][0], rcp[rid][MAX_CPS][1], 15.0, floatround(rcp[rid][3][4]));		//create race start boundaries
		}
		//case 2241-2255 -> Race Editor
		case 2202:	//set vehicle
		{
			if(race_editor[1] == 0) return 1;
			if(!response) 
			{
				RaceEditorClose(playerid);
				return 1; // cancel
			}
			rcp[MAX_RACES][5][4] = listitem;
			if(listitem == 5 || listitem == 6 || listitem == 7) rcp[MAX_RACES][1][4] = 3.0;	//cp type air
			else rcp[MAX_RACES][1][4] = 0.0;		//cp type normal
			RaceEditor2(playerid);
		}
		case 2203:	//cp diameter
		{
			if(race_editor[1] == 0) return 1;
			if(!response)
			{
				//DestroyDynamicRaceCP(race_editor[0]);
				DisablePlayerRaceCheckpoint(playerid);
				RaceEditor1(playerid);
			}
			else if(listitem == 0)
			{
				rcp[MAX_RACES][0][4] += 0.5;
				//DestroyDynamicRaceCP(race_editor[0]);
				DisablePlayerRaceCheckpoint(playerid);
				RaceEditor2(playerid);
			}
			else if(listitem == 1)
			{
				rcp[MAX_RACES][0][4] -= 0.5;
				//DestroyDynamicRaceCP(race_editor[0]);
				DisablePlayerRaceCheckpoint(playerid);
				RaceEditor2(playerid);
			}
			else
			{
				//DestroyDynamicRaceCP(race_editor[0]);
				DisablePlayerRaceCheckpoint(playerid);
				RaceEditor3(playerid);
			}
		}
		case 2204:	//max. participants
		{
			if(race_editor[1] == 0) return 1;
			new part = 0;
			if(!response) RaceEditor2(playerid);
			else if(sscanf(inputtext, "d", part)) 
			{
				SendClientMessage(playerid, 0xFF0000FF, "SERVER: Inserisci un numero valido!");
				RaceEditor3(playerid);
			}
			else
			{
				rcp[MAX_RACES][4][4] = float(part);
				RaceEditor4(playerid);
			}
		}
		case 2205:	//virtual world
		{
			if(race_editor[1] == 0) return 1;
			new vworld = 0;
			if(!response) RaceEditor3(playerid);
			else if(sscanf(inputtext, "d", vworld)) 
			{
				SendClientMessage(playerid, 0xFF0000FF, "SERVER: Inserisci un numero valido!");
				RaceEditor4(playerid);
			}
			else
			{
				if(vworld < 0)
				{
					SendClientMessage(playerid, 0xFF0000FF, "SERVER: Inserisci un numero valido!");
					RaceEditor4(playerid);
				}
				else
				{
					rcp[MAX_RACES][3][4] = float(vworld);
					SetVehicleVirtualWorld(GetPlayerVehicleID(playerid),vworld);
					SetPlayerVirtualWorld(playerid,vworld);
					RaceEditor5(playerid);
				}
			}
		}
		case 2206:	//set checkpoints
		{
			if(race_editor[1] == 0) return 1;
			if(!response) RaceEditor4(playerid);
			else race_editor[4] = 1;
			return 1;
		}
		case 2207:	//race name
		{
			if(race_editor[1] == 0) return 1;
			if(!response) 
			{
				RaceEditorClose(playerid);
				return 1; // cancel
			}
			else
			{
				new check[64];
				if(sscanf(inputtext,"s[64]",check))
				{
					SendClientMessage(playerid, 0xFF0000FF, "SERVER: Inserisci un nome valido!");
					RaceEditor6(playerid);
				}
				else
				{
					format(rname[MAX_RACES], sizeof(rname[]), "%s", inputtext);
					RaceEditor7(playerid);
				}
			}
		}
		case 2208:	//save
		{
			if(race_editor[1] == 0) return 1;
			if(!response) RaceEditor6(playerid);
			else RacefileCheck(playerid);
		}
		case 2209:	//overwrite
		{
			if(race_editor[1] == 0) return 1;
			if(!response) RaceEditor7(playerid);
			else RaceToFile(playerid);
		}
		case 2210:	//race settings
		{
			if(!response) return 1;		//cancel
			switch(listitem)
			{
				case 0:		//delete races
				{
					if(!response) RaceSettings(playerid);
					else
					{
						new race_sel[MAX_RACES * 64];		//63 char limitation to race name
						new race_ins[64];
						for(new i = 0; i < race_count; i++)		//read race names and creat race selection dialog
						{
							format(race_ins, sizeof(race_ins), "%s (%s)\r\n",rname[i],rfilename[i]);
							strins(race_sel, race_ins, strlen(race_sel));
						}
						ShowPlayerDialog(playerid,2211,DIALOG_STYLE_LIST,"Seleziona",race_sel,"Elimina", "Annulla");
					}
				}
				case 1:		//cp autorepair
				{
					if(cprepair) cprepair = false;
					else cprepair = true;
					RaceSettings(playerid);
				}
				case 2:		//start countdown
				{
					ShowPlayerDialog(playerid, 2213, DIALOG_STYLE_INPUT, "start countdown", "Inserisci il countdown d'inizio (secondi)", "Ok", "Annulla");
				}
				case 3:		//back to veh countdown
				{
					ShowPlayerDialog(playerid, 2214, DIALOG_STYLE_INPUT, "return countdown", "Inserisci il tempo disponibile per tornare al veicolo (secondi)", "Ok", "Annulla");
				}
				case 4:		//start freeze
				{
					if(sfreeze) sfreeze = false;
					else sfreeze = true;
					RaceSettings(playerid);
				}
				case 5:		//autostart
				{
					if(race[MAX_PLAYERS][1] + race[MAX_PLAYERS][2] == 0)
					{
						if(autotimer[0] == 1)
						{
							autotimer[0] = 0;
							KillTimer(autotimer[1]);
						}
						else 
						{
							autotimer[0] = 1;
							if(race_count == 0)
							{
								SendClientMessage(playerid, 0xFF0000FF, "SERVER: Nessuna gara trovata!");
								autotimer[0] = 0;
							}
							else AutoStart1();
						}
					}
					else SendClientMessage(playerid, 0xFF0000FF, "SERVER: Aspetta il termine della gara corrente.");
					RaceSettings(playerid);
				}
				case 6:		//autostart time
				{
					ShowPlayerDialog(playerid, 2215, DIALOG_STYLE_INPUT, "Autostart Time", "Inserisci un intervallo per l'autostart (minuti)", "Ok", "Annulla");
				}
				case 7:		//join time
				{
					ShowPlayerDialog(playerid, 2216, DIALOG_STYLE_INPUT, "Join Time", "Inserisci un intervallo per joinare (minuti)", "Ok", "Annulla");
				}
				case 8:		//autoend time
				{
					ShowPlayerDialog(playerid, 2217, DIALOG_STYLE_INPUT, "Autoend Time", "Inserisci un intervallo per terminare (minuti)", "Ok", "Annulla");
				}
			}
		}
		case 2211:	//delete races confirm
		{
			if(!response) RaceSettings(playerid);
			else
			{
				drace = listitem;
				new msg[128];
				format(msg, sizeof(msg), "Eliminare\r\n %s (%s)\r\n???", rfilename[drace], rname[drace]);
				ShowPlayerDialog(playerid, 2212, DIALOG_STYLE_MSGBOX, "{FF0000}ELIMINA", msg, "Elimina", "Annulla");
			}
		}
		case 2212:	//delete
		{
			if(!response) RaceSettings(playerid);
			else if(fremove(rfilename[drace]))
			{
				new msg[128];
				format(msg, sizeof(msg), "SERVER: %s (%s) eliminato.", rfilename[drace], rname[drace]);
				printf("Racefile ..%s eliminato", rfilename[drace]);
				SendClientMessage(playerid, 0xFF0000FF, msg);
				LoadRaces();
			}
			else
			{
				new msg[128];
				format(msg, sizeof(msg), "ERROR: %s (%s) non puo' essere eliminato.", rfilename[drace], rname[drace]);
				SendClientMessage(playerid, 0xFF0000FF, msg);
			}
		}
		case 2213:	//start countdown
		{
			if(!response) RaceSettings(playerid);
			else
			{
				if(sscanf(inputtext, "d", scount)) SendClientMessage(playerid, 0xFF0000FF, "ERROR: Inserisci un tempo valido.");
			}
			RaceSettings(playerid);
		}
		case 2214:	//back to veh countdown
		{
			if(!response) RaceSettings(playerid);
			else
			{
				if(sscanf(inputtext, "d", rettime)) SendClientMessage(playerid, 0xFF0000FF, "ERROR: Inserisci un tempo valido.");
			}
			RaceSettings(playerid);
		}
		case 2215:	//autostart time
		{
			if(!response) RaceSettings(playerid);
			else
			{
				if(sscanf(inputtext, "d", autotimer[2])) SendClientMessage(playerid, 0xFF0000FF, "ERROR: Inserisci un tempo valido.");
			}
			RaceSettings(playerid);
		}
		case 2216:	//join time
		{
			if(!response) RaceSettings(playerid);
			else
			{
				if(sscanf(inputtext, "d", autotimer[4])) SendClientMessage(playerid, 0xFF0000FF, "ERROR: Inserisci un tempo valido.");
			}
			RaceSettings(playerid);
		}
		case 2217:	//autoend time
		{
			if(!response) RaceSettings(playerid);
			else
			{
				if(sscanf(inputtext, "d", autotimer[6])) SendClientMessage(playerid, 0xFF0000FF, "ERROR: Inserisci un tempo valido.");
			}
			RaceSettings(playerid);
		}
	}
	return 0;
}

//***************************************************************************
//******************** textdraw related functions ***************************
//***************************************************************************

InitTextdraws()		//the info and announcement textdraws
{
	textdraws[MAX_PLAYERS][0] = TextDrawCreate(320.0, 10.0, ".");
	ftextdraw(textdraws[MAX_PLAYERS][0], 2);
	textdraws[MAX_PLAYERS][1] = TextDrawCreate(320.0, 20.0, ".");
	ftextdraw(textdraws[MAX_PLAYERS][1], 2);
	textdraws[MAX_PLAYERS][2] = TextDrawCreate(320.0, 100.0, ".");
	ftextdraw(textdraws[MAX_PLAYERS][2], 1);
	textdraws[MAX_PLAYERS][3] = TextDrawCreate(320.0, 140.0, ".");
	ftextdraw(textdraws[MAX_PLAYERS][3], 1);
	textdraws[MAX_PLAYERS][4] = TextDrawCreate(320.0, 180.0, ".");
	ftextdraw(textdraws[MAX_PLAYERS][4], 1);
	return 1;
}

DestroyTextdraws()
{
	TextDrawHideForAll(textdraws[MAX_PLAYERS][0]);
	TextDrawDestroy(textdraws[MAX_PLAYERS][0]);
	TextDrawHideForAll(textdraws[MAX_PLAYERS][1]);
	TextDrawDestroy(textdraws[MAX_PLAYERS][1]);
	TextDrawHideForAll(textdraws[MAX_PLAYERS][2]);
	TextDrawDestroy(textdraws[MAX_PLAYERS][2]);
	TextDrawHideForAll(textdraws[MAX_PLAYERS][3]);
	TextDrawDestroy(textdraws[MAX_PLAYERS][3]);
	TextDrawHideForAll(textdraws[MAX_PLAYERS][4]);
	TextDrawDestroy(textdraws[MAX_PLAYERS][4]);
	return 1;
}

ShowRaceStartedMsg(time)
{
	TextDrawSetString(textdraws[MAX_PLAYERS][2], rname[rid]);
	TextDrawSetString(textdraws[MAX_PLAYERS][3], "iniziata");
	TextDrawSetString(textdraws[MAX_PLAYERS][4], "partecipa con /race");
	TextDrawShowForAll(textdraws[MAX_PLAYERS][2]);
	TextDrawShowForAll(textdraws[MAX_PLAYERS][3]);
	TextDrawShowForAll(textdraws[MAX_PLAYERS][4]);
	SetTimer("HideRaceStartedMsg", 1000 * time, false);
	return 1;
}

public HideRaceStartedMsg()
{
	TextDrawHideForAll(textdraws[MAX_PLAYERS][2]);
	TextDrawHideForAll(textdraws[MAX_PLAYERS][3]);
	TextDrawHideForAll(textdraws[MAX_PLAYERS][4]);
	ShowRaceInfo();
	return 1;
}

ShowRaceInfo()
{
	new msg[128];
	format(msg, sizeof(msg), "%s iniziata", rname[rid]);
	TextDrawSetString(textdraws[MAX_PLAYERS][0], msg);
	TextDrawSetString(textdraws[MAX_PLAYERS][1], "Partecipa con /race");
	TextDrawShowForAll(textdraws[MAX_PLAYERS][0]);
	TextDrawShowForAll(textdraws[MAX_PLAYERS][1]);
	return 1;
}

HideRaceInfo()
{
	TextDrawHideForAll(textdraws[MAX_PLAYERS][0]);
	TextDrawHideForAll(textdraws[MAX_PLAYERS][1]);
	return 1;
}

public Countdown(delay)  //race Countdown
{
	if(count == delay)
	{
		TextDrawSetString(textdraws[MAX_PLAYERS][3], "VIA!");
		KillTimer(timer);
		count = 0;
		freeze = false;
		SetTimer("HideCountdown", 3000, false);
	}
	else
	{
		new string[4];
		format(string, sizeof(string), "%d", delay - count);
		if(count == 0)
		{
			TextDrawSetString(textdraws[MAX_PLAYERS][3], string);
			for (new i = 0; i < MAX_PLAYERS; i++)
			{
				if(race[i][2] == 1)
				{
					TextDrawShowForPlayer(i, textdraws[MAX_PLAYERS][3]);
				}
			}
		}
		TextDrawSetString(textdraws[MAX_PLAYERS][3], string);
		count++;
	}
	return 1;
}

public HideCountdown()
{
	TextDrawHideForAll(textdraws[MAX_PLAYERS][3]);
	return 1;
}

ShowPlayerFinishMsg(playerid)
{
	new position = floatround(rcp[rid][(race[playerid][1] - 1)][3]);
	switch(position)
	{
		case 1:
		{
			winmsg = true;
			new pName[MAX_PLAYER_NAME];
			GetPlayerName(playerid, pName, MAX_PLAYER_NAME);
			textdraws[playerid][2] = TextDrawCreate(320.0, 100.0, pName);
			ftextdraw(textdraws[playerid][2],1);
			textdraws[playerid][3] = TextDrawCreate(320.0, 140.0, "] ha vinto ]");
			ftextdraw(textdraws[playerid][3],1);
			textdraws[playerid][4] = TextDrawCreate(320.0, 180.0, "] Hai ] vinto ]");
			ftextdraw(textdraws[playerid][4],1);
			TextDrawShowForAll(textdraws[playerid][2]);
			TextDrawShowForAll(textdraws[playerid][3]);
			TextDrawHideForPlayer(playerid, textdraws[playerid][2]);
			TextDrawHideForPlayer(playerid, textdraws[playerid][3]);
			TextDrawShowForPlayer(playerid, textdraws[playerid][4]);
			SetTimerEx("HideWinMsg", 3000, false, "d", playerid);
		}
		case 2:
		{
			new pName[MAX_PLAYER_NAME];
			GetPlayerName(playerid, pName, MAX_PLAYER_NAME);
			textdraws[playerid][2] = TextDrawCreate(320.0, 100.0, pName);
			ftextdraw(textdraws[playerid][2],1);
			textdraws[playerid][3] = TextDrawCreate(320.0, 140.0, "] sei arrivato secondo ]");
			ftextdraw(textdraws[playerid][3],1);
			textdraws[playerid][4] = TextDrawCreate(320.0, 180.0, "sei arrivato secondo");
			ftextdraw(textdraws[playerid][4],1);
			if(!winmsg)
			{
				winmsg = true;
				TextDrawShowForAll(textdraws[playerid][2]);
				TextDrawShowForAll(textdraws[playerid][3]);
				TextDrawHideForPlayer(playerid, textdraws[playerid][2]);
				TextDrawHideForPlayer(playerid, textdraws[playerid][3]);
				SetTimerEx("HideWinMsg", 3000, false, "d", playerid);
			}
			else SetTimerEx("ShowPlayerFinishMsgDelayed", 500, false, "d", playerid);
			TextDrawShowForPlayer(playerid, textdraws[playerid][4]);
		}
		case 3:
		{
			new pName[MAX_PLAYER_NAME];
			GetPlayerName(playerid, pName, MAX_PLAYER_NAME);
			textdraws[playerid][2] = TextDrawCreate(320.0, 100.0, pName);
			ftextdraw(textdraws[playerid][2],1);
			textdraws[playerid][3] = TextDrawCreate(320.0, 140.0, "] sei arrivato terzo ]");
			ftextdraw(textdraws[playerid][3],1);
			textdraws[playerid][4] = TextDrawCreate(320.0, 180.0, "sei arrivato terzo");
			ftextdraw(textdraws[playerid][4],1);
			if(!winmsg)
			{
				winmsg = true;
				TextDrawShowForAll(textdraws[playerid][2]);
				TextDrawShowForAll(textdraws[playerid][3]);
				TextDrawHideForPlayer(playerid, textdraws[playerid][2]);
				TextDrawHideForPlayer(playerid, textdraws[playerid][3]);
				SetTimerEx("HideWinMsg", 3000, false, "d", playerid);
			}
			else SetTimerEx("ShowPlayerFinishMsgDelayed", 1000, false, "d", playerid);
			TextDrawShowForPlayer(playerid, textdraws[playerid][4]);
		}
		default :
		{
			new string[32];
			format(string, sizeof(string), "Sei arrivato %d", position);
			textdraws[playerid][4] = TextDrawCreate(320.0, 180.0, string);
			ftextdraw(textdraws[playerid][4],1);
			TextDrawShowForPlayer(playerid, textdraws[playerid][4]);
		}
	}
	SetTimerEx("HidePlayerFinishMsg", 3000, false, "d", playerid);
	return 1;
}

public ShowPlayerFinishMsgDelayed(playerid)
{
	if(winmsg) SetTimerEx("ShowPlayerFinishMsgDelayed", 500, false, "d", playerid);
	else
	{
		winmsg = true;
		TextDrawShowForAll(textdraws[playerid][2]);
		TextDrawShowForAll(textdraws[playerid][3]);
		TextDrawHideForPlayer(playerid, textdraws[playerid][2]);
		TextDrawHideForPlayer(playerid, textdraws[playerid][3]);
		SetTimerEx("HideWinMsg", 3000, false, "d", playerid);
	}
	return 1;
}

public HideWinMsg(playerid)
{
	TextDrawHideForAll(textdraws[playerid][2]);
	TextDrawHideForAll(textdraws[playerid][3]);
	TextDrawDestroy(textdraws[playerid][2]);
	TextDrawDestroy(textdraws[playerid][3]);
	winmsg = false;
	return 1;
}

public HidePlayerFinishMsg(playerid)
{
	TextDrawHideForPlayer(playerid, textdraws[playerid][4]);
	TextDrawDestroy(textdraws[playerid][4]);
	return 1;
}

ftextdraw(Text:drawID, style)
{
	switch(style)
	{
		case 0:				//checkpoint & pos racing style
		{
			TextDrawFont(drawID, 1);
			TextDrawAlignment(drawID, 2);
			TextDrawColor(drawID, 0xFF0000FF);
			TextDrawSetOutline(drawID, 1);
			TextDrawSetShadow(drawID, 0);
			TextDrawTextSize(drawID, 60, 170);
			TextDrawSetProportional(drawID, 1);
		}
		case 1:			//race enter & finish style
		{
			TextDrawAlignment(drawID, 2);
			TextDrawColor(drawID, 0xFF0000FF);
			TextDrawSetOutline(drawID, 1);
			TextDrawSetShadow(drawID, 0);
			TextDrawFont(drawID, 2);
			TextDrawLetterSize(drawID,0.8, 2.4);
			TextDrawSetProportional(drawID, 1);
		}
		case 2:		//race info style
		{
			TextDrawAlignment(drawID, 2);
			TextDrawColor(drawID, 0xFF0000FF);
			TextDrawSetOutline(drawID, 1);
			TextDrawSetShadow(drawID, 0);
			TextDrawFont(drawID, 2);
			TextDrawLetterSize(drawID, 0.4, 1.2);
			TextDrawSetProportional(drawID, 1);
		}
	}
	return 1;
}

public GetBack(playerid)		//get back to your car
{
	new string[4];
	format(string, sizeof(string), "%d", rettime - exitcounter[playerid]);
	if(exitcounter[playerid] == 0)
	{
		noveh[playerid] = true;
		textdraws[playerid][2] = TextDrawCreate(320.0, 100.0, "Ritorna");
		ftextdraw(textdraws[playerid][2],1);
		textdraws[playerid][3] = TextDrawCreate(320.0, 140.0, "al tuo veicolo");
		ftextdraw(textdraws[playerid][3],1);
		textdraws[playerid][4] = TextDrawCreate(320.0, 180.0, string);
		ftextdraw(textdraws[playerid][4],1);
		TextDrawShowForPlayer(playerid, textdraws[playerid][2]);
		TextDrawShowForPlayer(playerid, textdraws[playerid][3]);
		TextDrawShowForPlayer(playerid, textdraws[playerid][4]);
	}
	else TextDrawSetString(textdraws[playerid][4], string);
	exitcounter[playerid]++;
	if(exitcounter[playerid] - 1 == rettime)
	{
		ExitRace(playerid);
	}
	if(!noveh[playerid])
	{
		TextDrawHideForPlayer(playerid, textdraws[playerid][2]);
		TextDrawHideForPlayer(playerid, textdraws[playerid][3]);
		TextDrawHideForPlayer(playerid, textdraws[playerid][4]);
		TextDrawDestroy(textdraws[playerid][2]);
		TextDrawDestroy(textdraws[playerid][3]);
		TextDrawDestroy(textdraws[playerid][4]);
		exitcounter[playerid] = 0;
		KillTimer(exittimer[playerid]);
	}
	return 1;
}

ShowTimeRemaining()		//displays the time left to race start
{
	new msg[32];
	format(msg, sizeof(msg), "la gara inizia in %d min", autotimer[4] - autotimer[5]);
	TextDrawSetString(textdraws[MAX_PLAYERS][3], msg);
	TextDrawShowForAll(textdraws[MAX_PLAYERS][3]);
	SetTimer("HideTimeRemaining", 3000, false);
	return 1;
}

public HideTimeRemaining()
{
	TextDrawHideForAll(textdraws[MAX_PLAYERS][3]);
	return 1;
}

//***************************************************************************
//***************************** joining the race ****************************
//***************************************************************************

EventCheck(playerid,vehtype)  //see if the player has the right vehicle
{
	if(vehtype == 0) return 1;		//no veh needed
	else
	{
		switch(GetVehicleModel(GetPlayerVehicleID(playerid)))
		{
			//cars
			case 400, 401, 402, 404, 405, 409, 410, 411, 412, 413, 415, 416, 418, 419, 420, 421, 422, 424, 426, 429, 434, 436, 438,
				 439, 440, 442, 445, 451, 458, 459, 466, 467, 470, 474, 475, 477, 478, 479, 480, 482, 483, 489, 490, 491, 492, 494,
				 495, 496, 500, 502, 503, 504, 505, 506, 507, 516, 517, 518, 525, 526, 527, 528, 529, 531, 533, 534, 535, 536, 540,
				 541, 542, 543, 545, 546, 547, 549, 550, 551, 552, 554, 555, 556, 557, 558, 559, 560, 561, 562, 565, 567, 568, 571,
				 572, 573, 574, 575, 576, 579, 580, 582, 583, 585, 587, 589, 596, 597, 598, 599, 600, 601, 602, 603, 604, 605 : 
			{
				if(vehtype == 1) return 1;		// motorbikes, trucks, cars
				else if(vehtype == 2) return 1;    //  cars
				else return 0;		//wrong veh
			}
			//motorbikes
			case 462, 448, 581, 522, 461, 521, 523, 463, 586, 468, 471 :
			{
				if(vehtype == 1) return 1;		// bikes, trucks, cars
				else if(vehtype == 3) return 1;		// bikes
				else return 0;		//wrong veh
			}
			//trucks
			case 403, 406, 407, 408, 414, 427, 431, 433, 437, 443, 455, 456, 498, 514, 515, 524, 544, 578, 609, 423, 428, 508, 588 :
			{
				if(vehtype == 1) return 1;		// bikes, trucks, cars
				else if(vehtype == 4) return 1;		// trucks
				else return 0;		//wrong veh
			}
			//planes
			case 460, 476, 511, 512, 513, 519, 553, 593 :
			{
				if(vehtype == 5) return 1;		// planes
				else return 0;		//wrong veh
			}
			//helis
			case 548, 417, 487, 488, 497, 563, 469 :
			{
				if(vehtype == 6) return 1;		// heli
				else return 0;		//wrong veh
			}
			//boats
			case 472, 473, 493, 595, 484, 430, 453, 452, 446, 454 :
			{
				if(vehtype == 7) return 1;		// boat
				else return 0;		//wrong veh
			}
			//bikes
			case 509, 481, 510 :
			{
				if(vehtype == 8) return 1;		// bikes
				else return 0;		//wrong veh
			}
			default : return 0;
		}
	}
	return 1;
}

WVehicleMsg(playerid,vehtype)		//errormessage for wrong veh
{
	switch(vehtype)
	{
		case 1:{SendClientMessage(playerid, 0xFF0000FF, "SERVER: Hai bisogno di un veicolo di terra per partecipare! (Auto/Moto/Bici/Camion)");}
		case 2:{SendClientMessage(playerid, 0xFF0000FF, "SERVER: Hai bisogno di un auto per partecipare!");}
		case 3:{SendClientMessage(playerid, 0xFF0000FF, "SERVER: Hai bisogno di una moto per partecipare!");}
		case 4:{SendClientMessage(playerid, 0xFF0000FF, "SERVER: Hai bisogno di un camion per partecipare!");}
		case 5:{SendClientMessage(playerid, 0xFF0000FF, "SERVER: Hai bisogno di un aereo per partecipare! (No hydra/at400/andromeda)");}
		case 6:{SendClientMessage(playerid, 0xFF0000FF, "SERVER: Hai bisogno di un elicottero per partecipare! (No hunter/seasparrow)");}
		case 7:{SendClientMessage(playerid, 0xFF0000FF, "SERVER: Hai bisogno di una barca per partecipare!");}
		case 8:{SendClientMessage(playerid, 0xFF0000FF, "SERVER: Hai bisgno di una bici per partecipare!");}
	}
	return 1;
}

EnterRace(playerid)		//enter a race
{
	if(race[MAX_PLAYERS][1]==1)
	{
		if(race[playerid][2] == 1)
		{
			SendClientMessage(playerid, 0xFF0000FF, "ERROR: Stai gia' partecipando a questa gara! ~n~/exit per abbandonare");
		}
		else if(race[MAX_PLAYERS][0] == floatround(rcp[rid][4][4]))  //race full
		{
			SendClientMessage(playerid, 0xFF0000FF, "SERVER: La gara ha raggiunto il numero massimo di giocatori.");
			return 0;
		}
		else
		{
			if(EventCheck(playerid,floatround(rcp[rid][5][4])) == 1)
			{
				SaveKoords(playerid);
				DisArm(playerid);
				race[MAX_PLAYERS][0]++;
				race[playerid][2]=1;
				if(floatround(rcp[rid][5][4]) == 0)
				{
					SetPlayerPos(playerid,rcp[rid][MAX_CPS][0],rcp[rid][MAX_CPS][1],rcp[rid][MAX_CPS][2]);		//race spawn
					SetPlayerVirtualWorld(playerid,floatround(rcp[rid][3][4]));
				}
				else
				{
					new Float:zangle;
					zangle = atan2((rcp[rid][0][1] - rcp[rid][MAX_CPS][1]), (rcp[rid][0][0] - rcp[rid][MAX_CPS][0])) - 90.0;
					SetVehicleZAngle(GetPlayerVehicleID(playerid), zangle);		//set vehicle direction towards first cp
					SetVehiclePos(GetPlayerVehicleID(playerid),rcp[rid][MAX_CPS][0],rcp[rid][MAX_CPS][1],rcp[rid][MAX_CPS][2] + 2.0);		//race spawn
					SetVehicleVirtualWorld(GetPlayerVehicleID(playerid),floatround(rcp[rid][3][4]));
					SetPlayerVirtualWorld(playerid,floatround(rcp[rid][3][4]));
					//AddVehicleComponent(GetPlayerVehicleID(playerid),1010);		//nitro
					RepairVehicle(GetPlayerVehicleID(playerid));				//repair veh
					for(new i=0; i < MAX_PLAYERS; i++)
					{
						if(i != playerid) SetVehicleParamsForPlayer(GetPlayerVehicleID(playerid),i,0,1);
					}
					PlayerPlaySound(playerid,1133,0.0,0.0,0.0);
				}
			}
			else
			{
				WVehicleMsg(playerid,floatround(rcp[rid][5][4]));
			}
		}
	}
	else if(race[MAX_PLAYERS][2]==1)
	{
		SendClientMessage(playerid, 0xFF0000FF, "SERVER: Gara gia' iniziata.");
	}
	else
	{
		SendClientMessage(playerid, 0xFF0000FF, "SERVER: Nessuna gara in corso.");
	}
	return 1;
}

//*************************************************************************
//**************************** race checkpoints ***************************
//*************************************************************************

CreateFirstCP()		//creates the 1st checkpoint
{
	HideRaceInfo();
	new playerid = 0;
	for(new i = 0; i < MAX_PLAYERS; i++)
	{
		if(race[i][2] == 1)
		{
			playerid = i;
			new Float:x, Float:y, Float:z;
			GetVehiclePos(GetPlayerVehicleID(playerid),x,y,z);		//save in-race coordinates for start-freeze
			playerkoords[playerid+MAX_PLAYERS][0] = x;
			playerkoords[playerid+MAX_PLAYERS][1] = y;
			playerkoords[playerid+MAX_PLAYERS][2] = z;
			race[playerid][0] = CreateDynamicRaceCP(floatround(rcp[rid][1][4]),rcp[rid][race[playerid][1]][0],rcp[rid][race[playerid][1]][1],rcp[rid][(race[playerid][1])][2],rcp[rid][((race[playerid][1])+1)][0],rcp[rid][((race[playerid][1])+1)][1],rcp[rid][((race[playerid][1])+1)][2],rcp[rid][0][4],floatround(rcp[rid][3][4]),-1, playerid,300.0);
			SetPlayerMapIcon(playerid, rmapicons[playerid], rcp[rid][race[playerid][1]][0],rcp[rid][race[playerid][1]][1],rcp[rid][race[playerid][1]][2], 0, 0xFF0000FF, 1);
			new string[128];
			//textdraw with cp & position
			format(string, sizeof(string), "Posizione    %2d/%d",floatround(rcp[rid][race[playerid][1]][3]),race[MAX_PLAYERS][0]);
			textdraws[playerid][0] = TextDrawCreate(510, 360, string); 
			ftextdraw(textdraws[playerid][0],0);
			format(string, sizeof(string), "Checkpoint   0/%d",floatround(rcp[rid][2][4]));
			textdraws[playerid][1] = TextDrawCreate(510, 380, string); 
			ftextdraw(textdraws[playerid][1],0);
			TextDrawShowForPlayer(playerid, textdraws[playerid][0]);
			TextDrawShowForPlayer(playerid, textdraws[playerid][1]);
		}
	}
	freeze = true;		//activate freeze
	return 1;
}

public OnPlayerEnterDynamicRaceCP(playerid, checkpointid)
{
	if(race[playerid][2] == 1)
	{
		new string[128];
		rcp[rid][(race[playerid][1])][3]++;
		format(string, sizeof(string), "Posizione    %2d/%d",floatround(rcp[rid][race[playerid][1]][3]),race[MAX_PLAYERS][0]);
		TextDrawSetString(textdraws[playerid][0], string);
		format(string, sizeof(string), "Checkpoint %3d/%d",(race[playerid][1]) + 1,floatround(rcp[rid][2][4]));
		TextDrawSetString(textdraws[playerid][1], string);
		PlayerPlaySound(playerid,1138,0.0,0.0,0.0);
		race[playerid][1]++;
		RemovePlayerMapIcon(playerid, rmapicons[playerid]);
		if(race[playerid][1] == floatround(rcp[rid][2][4])) ShowPlayerFinishMsg(playerid);
		else SetPlayerMapIcon(playerid, rmapicons[playerid], rcp[rid][race[playerid][1]][0],rcp[rid][race[playerid][1]][1],rcp[rid][race[playerid][1]][2], 0, 0xFF0000FF, 1);
	}

	if(race[playerid][2] == 1)
	{
		if(cprepair)
		{
			new Float:chealth = 0;
			GetVehicleHealth(GetPlayerVehicleID(playerid),chealth);
			if(chealth < 1000.0){RepairVehicle(GetPlayerVehicleID(playerid));PlayerPlaySound(playerid,1133,0.0,0.0,0.0);}		//repair vehicle at every cp
		}
		if(race[playerid][1] < floatround(rcp[rid][2][4]))	//not last cp
		{
			DestroyDynamicRaceCP(race[playerid][0]);
			if((race[playerid][1] + 1) == floatround(rcp[rid][2][4])) race[playerid][0] = CreateDynamicRaceCP((floatround(rcp[rid][1][4])+1),rcp[rid][race[playerid][1]][0],rcp[rid][race[playerid][1]][1],rcp[rid][race[playerid][1]][2],rcp[rid][(race[playerid][1])+1][0],rcp[rid][(race[playerid][1])+1][1],rcp[rid][(race[playerid][1])+1][2],rcp[rid][0][4],floatround(rcp[rid][3][4]),-1, playerid,300.0);
			else race[playerid][0] = CreateDynamicRaceCP(floatround(rcp[rid][1][4]),rcp[rid][race[playerid][1]][0],rcp[rid][race[playerid][1]][1],rcp[rid][race[playerid][1]][2],rcp[rid][(race[playerid][1])+1][0],rcp[rid][(race[playerid][1])+1][1],rcp[rid][(race[playerid][1])+1][2],rcp[rid][0][4],floatround(rcp[rid][3][4]),-1, playerid,300.0);
		}
		else	//last cp
		{
			rcp[rid][floatround(rcp[rid][2][4])][3]++;
			DestroyDynamicRaceCP(race[playerid][0]);
			SetKoords(playerid);
			if(race[MAX_PLAYERS][0] == floatround(rcp[rid][floatround(rcp[rid][2][4])][3]))		//last player ends race
			{
				if(autotimer[0] == 1) KillTimer(autotimer[7]);
				EndRace();
			}
		}
	}
	return 1;
}

public OnPlayerLeaveDynamicRaceCP(playerid, checkpointid)
{
	/*if(race[playerid][2] == 1)
	{
		if(cprepair)
		{
			new Float:chealth = 0;
			GetVehicleHealth(GetPlayerVehicleID(playerid),chealth);
			if(chealth < 1000.0){RepairVehicle(GetPlayerVehicleID(playerid));PlayerPlaySound(playerid,1133,0.0,0.0,0.0);}		//repair vehicle at every cp
		}
		if(race[playerid][1] < floatround(rcp[rid][2][4]))	//not last cp
		{
			DestroyDynamicRaceCP(race[playerid][0]);
			if((race[playerid][1] + 1) == floatround(rcp[rid][2][4])) race[playerid][0] = CreateDynamicRaceCP((floatround(rcp[rid][1][4])+1),rcp[rid][race[playerid][1]][0],rcp[rid][race[playerid][1]][1],rcp[rid][race[playerid][1]][2],rcp[rid][(race[playerid][1])+1][0],rcp[rid][(race[playerid][1])+1][1],rcp[rid][(race[playerid][1])+1][2],rcp[rid][0][4],floatround(rcp[rid][3][4]),-1, playerid,300.0);
			else race[playerid][0] = CreateDynamicRaceCP(floatround(rcp[rid][1][4]),rcp[rid][race[playerid][1]][0],rcp[rid][race[playerid][1]][1],rcp[rid][race[playerid][1]][2],rcp[rid][(race[playerid][1])+1][0],rcp[rid][(race[playerid][1])+1][1],rcp[rid][(race[playerid][1])+1][2],rcp[rid][0][4],floatround(rcp[rid][3][4]),-1, playerid,300.0);
		}
		else	//last cp
		{
			rcp[rid][floatround(rcp[rid][2][4])][3]++;
			DestroyDynamicRaceCP(race[playerid][0]);
			SetKoords(playerid);
			if(race[MAX_PLAYERS][0] == floatround(rcp[rid][floatround(rcp[rid][2][4])][3]))		//last player ends race
			{
				if(autotimer[0] == 1) KillTimer(autotimer[7]);
				EndRace();
			}
		}
	}*/
	return 1;
}

//*************************************************************************
//************************ exiting / ending race **************************
//*************************************************************************

EndRace()  //resets race variables at race end
{
	if(race[MAX_PLAYERS][1] == 1) HideRaceInfo();
	for (new i = 0; i < (floatround(rcp[rid][2][4])+1); i++)
	{
		rcp[rid][i][3]=0;
	}
	race[MAX_PLAYERS][0]=0;
	race[MAX_PLAYERS][1]=0;
	race[MAX_PLAYERS][2]=0;
	rid = 0;
	DestroyDynamicArea(spawnarea);
	if(autotimer[0] == 1) autotimer[1] = SetTimer("AutoStart1", 60000 * autotimer[2], false);
	return 1;
}

ExitRace(playerid)
{
	SetKoords(playerid);
	if(noveh[playerid]) noveh[playerid] = false;
	race[MAX_PLAYERS][0]--;
	RemovePlayerMapIcon(playerid, rmapicons[playerid]);
	if(race[MAX_PLAYERS][0] == 0 && race[MAX_PLAYERS][2] == 1)
	{
		if(autotimer[0] == 1) KillTimer(autotimer[7]);
		EndRace();
	}
	return 1;
}

//*********************************************************************************
//********************** race file related ****************************************
//*********************************************************************************

LoadRaces()		//load races from files
{
	new filename[32];		//filename
	new line[64];			//stores a line read from a file
	new errormsg[64];		//used for errormessages
	new string[64];			//used for other messages
	race_count = 0;			//reset race counter

	
	for(new i = 0; i < MAX_RACES; i++)
	{
		new cp_count = 0;		//checkpoint counter
		if(i < 10) 
		{
			format(filename, sizeof(filename), "/races/race0%d.txt", i);
			format(rfilename[race_count], sizeof(rfilename[]), "/races/race0%d.txt", i);
		}
		else
		{
			format(filename, sizeof(filename), "/races/race%d.txt", i);
			format(rfilename[race_count], sizeof(rfilename[]), "/races/race%d.txt", i);
		}
		if(fexist(filename))	//check if the racefile exists
		{
			new lines_read = 0;
			new File:racefile = fopen(filename, io_read);		//open file
			format(string, sizeof(string), "...Loading %s",filename);
			print(string);
			while(fread(racefile, line))		//read from file
			{
				switch(lines_read)
				{
					case 0:			//racename
					{
						new tempstr[64];
						for(new z = 0; z < 64; z++)
						{
							new tempchar[2];
							format(tempchar, sizeof(tempchar), "%c",line[z]);
							if(!strcmp(tempchar, ";")) break;
							tempstr[z] = tempchar[0];
						}
						format(errormsg, sizeof(errormsg), "Error reading racename in %s",filename);
						if(sscanf(tempstr, "s[64]", rname[race_count])) return print(errormsg);
						format(string, sizeof(string), " <%s>",rname[race_count]);
						print(string);
					}
					case 1:			//cp diameter
					{
						new tempstr[32];
						for(new z = 0; z < 32; z++)
						{
							new tempchar[2];
							format(tempchar, sizeof(tempchar), "%c",line[z]);
							if(!strcmp(tempchar, ";")) break;
							tempstr[z] = tempchar[0];
						}
						format(errormsg, sizeof(errormsg), "Error reading cp diameter in %s",filename);
						if(sscanf(tempstr, "f", rcp[race_count][0][4])) return print(errormsg);
					}
					case 2:			//cp type
					{
						new tempstr[32];
						for(new z = 0; z < 32; z++)
						{
							new tempchar[2];
							format(tempchar, sizeof(tempchar), "%c",line[z]);
							if(!strcmp(tempchar, ";")) break;
							tempstr[z] = tempchar[0];
						}
						format(errormsg, sizeof(errormsg), "Error reading cp type in %s",filename);
						if(sscanf(tempstr, "f", rcp[race_count][1][4])) return print(errormsg);
					}
					case 3:			//number of cps
					{
						new tempstr[32];
						for(new z = 0; z < 32; z++)
						{
							new tempchar[2];
							format(tempchar, sizeof(tempchar), "%c",line[z]);
							if(!strcmp(tempchar, ";")) break;
							tempstr[z] = tempchar[0];
						}
						format(errormsg, sizeof(errormsg), "Error reading number of cps in %s",filename);
						if(sscanf(tempstr, "f", rcp[race_count][2][4])) return print(errormsg);
					}
					case 4:			//virtual world
					{
						new tempstr[32];
						for(new z = 0; z < 32; z++)
						{
							new tempchar[2];
							format(tempchar, sizeof(tempchar), "%c",line[z]);
							if(!strcmp(tempchar, ";")) break;
							tempstr[z] = tempchar[0];
						}
						format(errormsg, sizeof(errormsg), "Error reading virtual world in %s",filename);
						if(sscanf(tempstr, "f", rcp[race_count][3][4])) return print(errormsg);
					}
					case 5:			//max participants
					{
						new tempstr[32];
						for(new z = 0; z < 32; z++)
						{
							new tempchar[2];
							format(tempchar, sizeof(tempchar), "%c",line[z]);
							if(!strcmp(tempchar, ";")) break;
							tempstr[z] = tempchar[0];
						}
						format(errormsg, sizeof(errormsg), "Error reading max participants in %s",filename);
						if(sscanf(tempstr, "f", rcp[race_count][4][4])) return print(errormsg);
					}
					case 6:			//vehicle requirement
					{
						new tempstr[32];
						for(new z = 0; z < 32; z++)
						{
							new tempchar[2];
							format(tempchar, sizeof(tempchar), "%c",line[z]);
							if(!strcmp(tempchar, ";")) break;
							tempstr[z] = tempchar[0];
						}
						format(errormsg, sizeof(errormsg), "Error reading vehicle requirements in %s",filename);
						if(sscanf(tempstr, "f", rcp[race_count][5][4])) return print(errormsg);
					}
					case 7:			//free
					{
						new tempstr[32];
						for(new z = 0; z < 32; z++)
						{
							new tempchar[2];
							format(tempchar, sizeof(tempchar), "%c",line[z]);
							if(!strcmp(tempchar, ";")) break;
							tempstr[z] = tempchar[0];
						}
						format(errormsg, sizeof(errormsg), "Error reading unused var 1 in %s",filename);
						if(sscanf(tempstr, "f", rcp[race_count][6][4])) return print(errormsg);
					}
					case 8:			//free
					{
						new tempstr[32];
						for(new z = 0; z < 32; z++)
						{
							new tempchar[2];
							format(tempchar, sizeof(tempchar), "%c",line[z]);
							if(!strcmp(tempchar, ";")) break;
							tempstr[z] = tempchar[0];
						}
						format(errormsg, sizeof(errormsg), "Error reading unused var 2 in %s",filename);
						if(sscanf(tempstr, "f", rcp[race_count][7][4])) return print(errormsg);
					}
					case 9:			//free
					{
						new tempstr[32];
						for(new z = 0; z < 32; z++)
						{
							new tempchar[2];
							format(tempchar, sizeof(tempchar), "%c",line[z]);
							if(!strcmp(tempchar, ";")) break;
							tempstr[z] = tempchar[0];
						}
						format(errormsg, sizeof(errormsg), "Error reading unused var 3 in %s",filename);
						if(sscanf(tempstr, "f", rcp[race_count][8][4])) return print(errormsg);
					}
					case 10:			//free
					{
						new tempstr[32];
						for(new z = 0; z < 32; z++)
						{
							new tempchar[2];
							format(tempchar, sizeof(tempchar), "%c",line[z]);
							if(!strcmp(tempchar, ";")) break;
							tempstr[z] = tempchar[0];
						}
						format(errormsg, sizeof(errormsg), "Error reading unused var 4 in %s",filename);
						if(sscanf(tempstr, "f", rcp[race_count][9][4])) return print(errormsg);
					}
					case 11:			//race spawn
					{
						new index = 0;
						new tempstrx[32];		//spawn X
						for(new z = 0; z < 14; z++)
						{
							new tempchar[2];
							format(tempchar, sizeof(tempchar), "%c",line[z]);
							if(!strcmp(tempchar, ",")) break;
							tempstrx[z] = tempchar[0];
						}
						index += (strlen(tempstrx) + 1);
						format(errormsg, sizeof(errormsg), "Error reading X-spawn in %s",filename);
						if(sscanf(tempstrx, "f", rcp[race_count][MAX_CPS][0])) return print(errormsg);
						
						new tempstry[32];		//spawn Y
						for(new z = 0; z < 14; z++)
						{
							new tempchar[2];
							format(tempchar, sizeof(tempchar), "%c",line[z + index]);
							if(!strcmp(tempchar, ",")) break;
							tempstry[z] = tempchar[0];
						}
						index += (strlen(tempstry) + 1);
						format(errormsg, sizeof(errormsg), "Error reading Y-spawn in %s",filename);
						if(sscanf(tempstry, "f", rcp[race_count][MAX_CPS][1])) return print(errormsg);
						
						new tempstrz[32];		//spawn Z
						for(new z = 0; z < 14; z++)
						{
							new tempchar[2];
							format(tempchar, sizeof(tempchar), "%c",line[z + index]);
							if(!strcmp(tempchar, ";")) break;
							tempstrz[z] = tempchar[0];
						}
						format(errormsg, sizeof(errormsg), "Error reading Z-spawn in %s",filename);
						if(sscanf(tempstrz, "f", rcp[race_count][MAX_CPS][2])) return print(errormsg);
					}
					default :		//race checkpoints
					{
						new index = 0;
						new tempstrx[32];		//cp X
						for(new z = 0; z < 14; z++)
						{
							new tempchar[2];
							format(tempchar, sizeof(tempchar), "%c",line[z]);
							if(!strcmp(tempchar, ",")) break;
							tempstrx[z] = tempchar[0];
						}
						index += (strlen(tempstrx) + 1);
						format(errormsg, sizeof(errormsg), "Error reading X at cp %d in %s",cp_count,filename);
						if(sscanf(tempstrx, "f", rcp[race_count][cp_count][0])) return print(errormsg);
						
						new tempstry[32];		//cp Y
						for(new z = 0; z < 14; z++)
						{
							new tempchar[2];
							format(tempchar, sizeof(tempchar), "%c",line[z + index]);
							if(!strcmp(tempchar, ",")) break;
							tempstry[z] = tempchar[0];
						}
						index += (strlen(tempstry) + 1);
						format(errormsg, sizeof(errormsg), "Error reading Y at cp %d in %s",cp_count,filename);
						if(sscanf(tempstry, "f", rcp[race_count][cp_count][1])) return print(errormsg);
						
						new tempstrz[32];		//cp Z
						for(new z = 0; z < 14; z++)
						{
							new tempchar[2];
							format(tempchar, sizeof(tempchar), "%c",line[z + index]);
							if(!strcmp(tempchar, ";")) break;
							tempstrz[z] = tempchar[0];
						}
						format(errormsg, sizeof(errormsg), "Error reading Z at cp %d in %s",cp_count,filename);
						if(sscanf(tempstrz, "f", rcp[race_count][cp_count][2])) return print(errormsg);
						cp_count++;
					}
				}
				lines_read++;
			}
			fclose(racefile);
			format(errormsg, sizeof(errormsg), "Wrong number of checkpoints in %s", filename);
			if(cp_count != floatround(rcp[race_count][2][4])) return print(errormsg);
			print("...Done");
			race_count++;
		}
	}
	format(string, sizeof(string), "  Loaded %d Races",race_count);
	print(string);
	return 1;
}

RaceToFile(playerid)
{
	SendClientMessage(playerid, 0x00FF00FF, "...writing racefile");
	new filename[32];		//filename
	new line[64];			//stores a line read from a file
	//set filename
	for(new i = 0; i < MAX_RACES; i++)
	{
		if(i < 10) format(filename, sizeof(filename), "/races/race0%d.txt", i);
		else format(filename, sizeof(filename), "/races/race%d.txt", i);
		if(!fexist(filename)) break;		//check if the racefile exists
	}		
	new File:racefile = fopen(filename, io_readwrite);		//open file
	format(line,sizeof(line),"%s;	Racename\r\n", rname[MAX_RACES]);	//racename
	fwrite(racefile,line);
	format(line,sizeof(line),"%f;	Checkpoint size\r\n", rcp[MAX_RACES][0][4]);	//cp size
	fwrite(racefile,line);
	format(line,sizeof(line),"%f;	Checkpoint type\r\n", rcp[MAX_RACES][1][4]);	//cp type
	fwrite(racefile,line);
	format(line,sizeof(line),"%f;	number of cps\r\n", rcp[MAX_RACES][2][4]);	//cp number
	fwrite(racefile,line);
	format(line,sizeof(line),"%f;	worldid\r\n", rcp[MAX_RACES][3][4]);	//worldid
	fwrite(racefile,line);
	format(line,sizeof(line),"%f;	max players\r\n", rcp[MAX_RACES][4][4]);	//max players
	fwrite(racefile,line);
	format(line,sizeof(line),"%f;	needed vehicle\r\n", rcp[MAX_RACES][5][4]);	//needed veh
	fwrite(racefile,line);
	format(line,sizeof(line),"%f;	unused 1\r\n", rcp[MAX_RACES][6][4]);	//unused atm
	fwrite(racefile,line);
	format(line,sizeof(line),"%f;	unused 2\r\n", rcp[MAX_RACES][7][4]);	//unused atm
	fwrite(racefile,line);
	format(line,sizeof(line),"%f;	unused 3\r\n", rcp[MAX_RACES][8][4]);	//unused atm
	fwrite(racefile,line);
	format(line,sizeof(line),"%f;	unused 4\r\n", rcp[MAX_RACES][9][4]);	//unused atm
	fwrite(racefile,line);
	format(line,sizeof(line),"%f,", rcp[MAX_RACES][MAX_CPS][0]);	//spawn x
	fwrite(racefile,line);
	format(line,sizeof(line),"%f,", rcp[MAX_RACES][MAX_CPS][1]);	//spawn y
	fwrite(racefile,line);
	format(line,sizeof(line),"%f;	Race Spawn\r\n", rcp[MAX_RACES][MAX_CPS][2]);	//spawn z
	fwrite(racefile,line);
	for(new i = 0; i < rcp[MAX_RACES][2][4]; i++)		//write checkpoints
	{
		format(line,sizeof(line),"%f,", rcp[MAX_RACES][i][0]);	//cp x
		fwrite(racefile,line);
		format(line,sizeof(line),"%f,", rcp[MAX_RACES][i][1]);	//cp y
		fwrite(racefile,line);
		format(line,sizeof(line),"%f;\r\n", rcp[MAX_RACES][i][2]);	//cp z
		fwrite(racefile,line);
	}
	fclose(racefile);
	SendClientMessage(playerid, 0x00FF00FF, "...Done");
	print("...Done");
	if(LoadRaces() != 1)
	{
		SendClientMessage(playerid, 0xFF0000FF, "SERVER: Error loading race files.");
		SendClientMessage(playerid, 0xFF0000FF, "See logfile for detailled information.");
	}
	else SendClientMessage(playerid, 0xFF0000FF, "SERVER: Racefiles reloaded.");
	RaceEditorClose(playerid);
	return 1;
}

RacefileCheck(playerid)
{
	new filename[32];		//filename
	if((race_count - 1) < 10) format(filename, sizeof(filename), "/races/race0%d.txt", race_count);
	else format(filename, sizeof(filename), "/races/race%d.txt", race_count);
	if(fexist(filename)) ShowPlayerDialog(playerid,2209,DIALOG_STYLE_MSGBOX,"Sovrascrivere?","Il racefile esiste gia', vuoi sovrascrivere?\r\n","Sovrascrivi","Indietro");
	else RaceToFile(playerid);
}

//*******************************************************************************
//*************************** race editor related *******************************
//*******************************************************************************

RaceEditor1(playerid)		//veh class
{
	if(race_count == MAX_RACES) return SendClientMessage(playerid, 0xFF0000FF, "SERVER: Troppe gare.");
	rcp[MAX_RACES][0][4] = 8.0;
	SendClientMessage(playerid, 0xFF0000FF, "SERVER: Puoi chiudere l'editor con /end");
	ShowPlayerDialog(playerid,2202,DIALOG_STYLE_LIST,"Scegli classe di veicoli","Tutti\r\nTerra (Auto,Moto,Bici,Camion)\r\nAuto\r\nMoto\r\nCamion\r\nAerei\r\nElicotteri\r\nBarche\r\nBici","Continua","Annulla");
	return 1;
}

RaceEditor2(playerid)		//cp diameter
{
	new caption[32];
	new Float:x, Float:y, Float:z;
	if(IsPlayerInAnyVehicle(playerid) == 1)
	{
		new Float:ang;
		GetVehiclePos(GetPlayerVehicleID(playerid),x,y,z);
		GetVehicleZAngle(GetPlayerVehicleID(playerid),ang);
		x += ((floatsin(ang, degrees)) * -15.0);
		y += ((floatcos(ang, degrees)) * 15.0);
	}
	else
	{
		new Float:ang;
		GetPlayerPos(GetPlayerVehicleID(playerid),x,y,z);
		GetPlayerFacingAngle(playerid,ang);
		x += ((floatsin(ang, degrees)) * -5.0);
		y += ((floatcos(ang, degrees)) * 5.0);
	}
	SetPlayerRaceCheckpoint(playerid, floatround(rcp[MAX_RACES][1][4]) + 1, x, y, z, x+10, y+10, z, rcp[MAX_RACES][0][4]);
	//CreateDynamicRaceCP(floatround(rcp[MAX_RACES][1][4]) + 1,x,y,z,x+10,y+10,z,rcp[MAX_RACES][0][4],0,-1,playerid,300.0);
	format(caption, sizeof(caption), "Grandezza checkpoint {FF0000}%.1f",rcp[MAX_RACES][0][4]);
	ShowPlayerDialog(playerid,2203,DIALOG_STYLE_LIST,caption,"Piu' largo <->\r\nPiu' stretto >-<\r\nSalva","Continua","Indietro");
	return 1;
}

RaceEditor3(playerid)		//max. participants
{
	ShowPlayerDialog(playerid,2204,DIALOG_STYLE_INPUT,"Massimo partecipanti","Inserisci il numero massimo di partecipanti.","Continua","Indietro");
	return 1;
}

RaceEditor4(playerid)		//set virtual world
{
	ShowPlayerDialog(playerid,2205,DIALOG_STYLE_INPUT,"Virtual World","Inserisci il Virtual World per questa gara. (inserisci 0 se non sai cosa inserire)","Continua","Indietro");
	return 1;
}

RaceEditor5(playerid)		//place cps
{
	ShowPlayerDialog(playerid,2206,DIALOG_STYLE_MSGBOX,"Inserimento checkpoint","Pronto per piazzare i checkpoint.","Continua","Indietro");
	SendClientMessage(playerid, 0x0000FFFF, "Usa  ~k~~VEHICLE_FIREWEAPON~  per piazzare i checkpoint. (IL PRIMO CHECKPOINT E' LO SPAWN DELLA GARA)");
	SendClientMessage(playerid, 0x0000FFFF, "UsA  ~k~~VEHICLE_HORN~  per piazzare l'arrivo della gara.");
	return 1;
}

public OnPlayerKeyStateChange(playerid, newkeys, oldkeys)
{
	if((newkeys & KEY_FIRE) && !(oldkeys & KEY_FIRE) && race_editor[3] == playerid && race_editor[4] != 0)		//place cps
	{
		if(race_editor[4] == 1)
		{
			new Float:x,Float:y,Float:z;
			GetPlayerPos(playerid,x,y,z);
			rcp[MAX_RACES][MAX_CPS][0] = x;
			rcp[MAX_RACES][MAX_CPS][1] = y;
			rcp[MAX_RACES][MAX_CPS][2] = z - 0.5;
			race_editor[4]++;
			SendClientMessage(playerid, 0x00FF00FF, "EDITOR: Spawn della gara impostato.");
		}
		else
		{
			new msg[32];
			new Float:x,Float:y,Float:z;
			GetPlayerPos(playerid,x,y,z);
			rcp[MAX_RACES][race_editor[2]][0] = x;
			rcp[MAX_RACES][race_editor[2]][1] = y;
			rcp[MAX_RACES][race_editor[2]][2] = z - 0.5;
			race_editor[2]++;
			format(msg,sizeof(msg),"EDITOR: Piazzato checkpoint %d.",race_editor[2]);
			SendClientMessage(playerid, 0x00FF00FF, msg);
		}
	}
	if((newkeys & KEY_CROUCH) && !(oldkeys & KEY_CROUCH) && race_editor[3] == playerid && race_editor[4] == 2)		//place last cp
	{
		race_editor[4] = 0;		//disable checkpoint placing
		new Float:x,Float:y,Float:z;
		GetPlayerPos(playerid,x,y,z);
		rcp[MAX_RACES][race_editor[2]][0] = x;
		rcp[MAX_RACES][race_editor[2]][1] = y;
		rcp[MAX_RACES][race_editor[2]][2] = z - 0.5;
		race_editor[2]++;
		rcp[MAX_RACES][2][4] = race_editor[2];		//set number of checkpoints
		SendClientMessage(playerid, 0x00FF00FF, "EDITOR: Piazziato arrivo della gara");
		RaceEditor6(playerid);
	}		
	return 1;
}

RaceEditor6(playerid)		//race name
{
	ShowPlayerDialog(playerid,2207,DIALOG_STYLE_INPUT,"Nome gara","Inserisci il nome della gara. (max. 63 chars)","Continua","Annulla");
	return 1;
}

RaceEditor7(playerid)		//save race
{
	ShowPlayerDialog(playerid,2208,DIALOG_STYLE_MSGBOX,"Salva","Salvare la gara?","Continua","Indietro");
	return 1;
}

RaceEditorClose(playerid)
{
	for(new i = 0; i < race_editor[2]; i++)		//reset temp race values
	{
		for(new z = 0; z < 5; z++)
		{
			rcp[MAX_RACES][i][z] = 0.0;
		}
	}
	
	for(new i = 0; i < 3; i++)		//reset temp race spawn
	{
		rcp[MAX_RACES][MAX_CPS][i] = 0.0;
	}

	for(new i = 0; i < 5; i++)		//reset race ed values
	{
		race_editor[i] = 0;
	}
	race_editor[3] = -1;
	race_editor[1] = 0;
	
	format(rname[MAX_RACES],sizeof(rname[]),"");		//reset race name
	SetVehicleVirtualWorld(GetPlayerVehicleID(playerid),0);
	SetPlayerVirtualWorld(playerid,0);
	SendClientMessage(playerid, 0xFF0000FF, "SERVER: Editor chiuso.");
	return 1;
}

//**************************************************************************************
//****************************** automatic race control*********************************
//**************************************************************************************

public AutoStart1()
{
	rid = random(race_count);		//set race ID
	race[MAX_PLAYERS][1] = 1;	//race initialized
	ShowRaceStartedMsg(10);
	spawnarea = CreateDynamicCircle(rcp[rid][MAX_CPS][0], rcp[rid][MAX_CPS][1], 55.0, floatround(rcp[rid][3][4]));		//create race start boundaries
	race[MAX_PLAYERS][0] = 0;
	autotimer[3] = SetTimer("AutoStart2", 60000, true);
	return 1;
}

public AutoStart2()
{
	autotimer[5]++;
	if(autotimer[5] == autotimer[4])
	{
		if(race[MAX_PLAYERS][0] > 1)
		{
			KillTimer(autotimer[3]);
			autotimer[5] = 0;
			race[MAX_PLAYERS][1]=0;		//set race status from "initilized"
			race[MAX_PLAYERS][2]=1;		//to "running"
			CreateFirstCP();
			timer = SetTimerEx("Countdown", 1000, true, "i", scount);
			autotimer[7] = SetTimer("AutoEnd1", (60000 * autotimer[6]) - 30000, false);
		}
		else
		{
			count = 30;
			KillTimer(autotimer[3]);
			autotimer[5] = 0;
			AutoEnd1();
		}
	}
	else ShowTimeRemaining();
	return 1;
}

public AutoEnd1()
{
	if(race[MAX_PLAYERS][2] == 1 || race[MAX_PLAYERS][1] == 1) timer = SetTimer("AutoEnd2", 1000, true);
	return 1;
}

public AutoEnd2()
{
	new delay = 30;
	if(race[MAX_PLAYERS][2] == 1 || race[MAX_PLAYERS][1] == 1)
	{
		if(count == delay)
		{
			KillTimer(timer);
			count = 0;
			TextDrawHideForAll(textdraws[MAX_PLAYERS][2]);
			TextDrawHideForAll(textdraws[MAX_PLAYERS][3]);
			for (new i = 0; i < MAX_PLAYERS; i++)
			{
				if(race[i][2] == 1)		//kick players out of race
				{
					SetKoords(i);
					noveh[i] = false;
					RemovePlayerMapIcon(i, rmapicons[i]);
					SendClientMessage(i, 0xFF0000FF, "SERVER: Questa gara e' stata terminata!");
				}
			}
			EndRace();
		}
		else
		{
			new string[32];
			format(string, sizeof(string), "in %d secondi", delay - count);
			if(count == 0)
			{
				TextDrawSetString(textdraws[MAX_PLAYERS][2], "Race will end");
				TextDrawSetString(textdraws[MAX_PLAYERS][3], string);
				for (new i = 0; i < MAX_PLAYERS; i++)
				{
					if(race[i][2] == 1)
					{
						TextDrawShowForPlayer(i, textdraws[MAX_PLAYERS][2]);
						TextDrawShowForPlayer(i, textdraws[MAX_PLAYERS][3]);
					}
				}
			}
			TextDrawSetString(textdraws[MAX_PLAYERS][3], string);
			count++;
		}
	}
	else
	{
		KillTimer(timer);
		TextDrawHideForAll(textdraws[MAX_PLAYERS][2]);
		TextDrawHideForAll(textdraws[MAX_PLAYERS][3]);
	}
	return 1;
}

//***************************************************************
//****************************** misc ***************************
//***************************************************************

RaceSettings(playerid)
{
	new list[256],set1[16],set2[16],set3[16];
	if(cprepair) format(set1, sizeof(set1), "{00FF00}ON");		//auto repair
	else format(set1, sizeof(set1), "{FF0000}OFF");
	if(sfreeze) format(set2, sizeof(set2), "{00FF00}ON");		//start freeze
	else format(set2, sizeof(set2), "{FF0000}OFF");
	if(autotimer[0] == 1) format(set3, sizeof(set3), "{00FF00}ON");		//race autostart
	else format(set3, sizeof(set3), "{FF0000}OFF");
	format(list, sizeof(list), "Elimina gare\r\nRipara al cp		%s\r\nCountdown inizio		%d sec\r\nTorna all'auto		%d sec\r\nStart Freeze		%s\r\nRace Autostart		%s\r\nAutostart every		%d min\r\nAutostart Jointime	%d min\r\nAutoend after		%d min",set1,scount,rettime,set2,set3,autotimer[2],autotimer[4],autotimer[6]);
	ShowPlayerDialog(playerid, 2210, DIALOG_STYLE_LIST, "Race Settings", list, "Select", "Cancel");
	return 1;
}

DisArm(playerid)		//DisArms a player before entering race
{
	for (new i = 0; i < 13; i++)
	{
		GetPlayerWeaponData(playerid, i, weapons[playerid][i][0], weapons[playerid][i][1]);
	}
	ResetPlayerWeapons(playerid);
	return 1;
}

ReArm(playerid)		//returns player weapons
{
	for (new i = 0; i < 13; i++)
	{
		GivePlayerWeapon(playerid, weapons[playerid][i][0], weapons[playerid][i][1]);
		weapons[playerid][i][0] = 0;
		weapons[playerid][i][1] = 0;
	}
	return 1;
}

SaveKoords(playerid)  //save playercoordinates
{
	new Float:x, Float:y, Float:z;
	GetPlayerPos(playerid, x, y, z);
	playerkoords[playerid][0] = x;
	playerkoords[playerid][1] = y;
	playerkoords[playerid][2] = z;

	return 1;
}

SetKoords(playerid)  //sets player back to where he was before entering the race and returns the weapons
{
	/*if(floatround(rcp[rid][5][4]) == 0 || IsPlayerInAnyVehicle(playerid) == 0)
	{
		SetPlayerPos(playerid, playerkoords[playerid][0], playerkoords[playerid][1], playerkoords[playerid][2]);
		SetPlayerVirtualWorld(playerid,0);
	}
	else
	{
		SetVehiclePos(GetPlayerVehicleID(playerid), playerkoords[playerid][0], playerkoords[playerid][1], playerkoords[playerid][2]);
		SetVehicleVirtualWorld(GetPlayerVehicleID(playerid), 0);
		SetPlayerVirtualWorld(playerid, 0);
		RepairVehicle(GetPlayerVehicleID(playerid));				//repair veh
		for(new i=0; i < MAX_PLAYERS; i++)		//unlock
		{
			if(i != playerid) SetVehicleParamsForPlayer(GetPlayerVehicleID(playerid),i,0,0);
		}
	}*/
	ReArm(playerid);
	if(race[MAX_PLAYERS][2] == 1)
	{
		TextDrawHideForPlayer(playerid, textdraws[playerid][0]);
		TextDrawHideForPlayer(playerid, textdraws[playerid][1]);
		TextDrawDestroy(textdraws[playerid][0]);
		TextDrawDestroy(textdraws[playerid][1]);
	}
	race[playerid][0]=0;
	race[playerid][1]=0;
	race[playerid][2]=0;
	return 1;
}

public OnPlayerConnect(playerid)
{
	if(race[MAX_PLAYERS][1] == 1)		//show race info on player connect
	{
		TextDrawShowForPlayer(playerid, textdraws[MAX_PLAYERS][0]);
		TextDrawShowForPlayer(playerid, textdraws[MAX_PLAYERS][1]);
	}
	return 1;
}

public OnPlayerDeath(playerid,killerid,reason)		//kick player out of race on death
{
	if(race[playerid][2] == 1)
	{
		ExitRace(playerid);
	}
	if(race_editor[3] == playerid) RaceEditorClose(playerid);
	return 1;
}

public OnPlayerDisconnect(playerid, reason)		//kick player out of race on dc
{
	if(race[playerid][2] == 1)
	{
		ExitRace(playerid);
	}
	if(race_editor[3] == playerid) RaceEditorClose(playerid);
	return 1;
}

public OnPlayerUpdate(playerid)
{
	//freeze at race start
	if(race[playerid][2] == 1 && freeze && sfreeze) SetVehiclePos(GetPlayerVehicleID(playerid),playerkoords[playerid+MAX_PLAYERS][0], playerkoords[playerid+MAX_PLAYERS][1], playerkoords[playerid+MAX_PLAYERS][2]);

	
	return 1;
}


public OnPlayerStateChange(playerid, newstate, oldstate)
{
	if(newstate == PLAYER_STATE_DRIVER)
	{
		playerveh[GetPlayerVehicleID(playerid)] = playerid;
		vehplayer[playerid] = GetPlayerVehicleID(playerid);
	}
	if(oldstate == PLAYER_STATE_DRIVER)
	{
		OnPlayerExitVehicleEx(playerid,vehplayer[playerid]);
		playerveh[vehplayer[playerid]] = -1;
		vehplayer[playerid] = -1;
	}
	return 1;
}

OnPlayerExitVehicleEx(playerid, vehicleid)		//is called when a player exits a vehicle in any way (including falling off a motorbike & dying)
{
	if(race[playerid][2] == 1) exittimer[playerid] = SetTimerEx("GetBack", 1000, true, "d", playerid);
	if(vehicleid == vehicleid) return 1;
	return 1;
}
		
public OnPlayerEnterVehicle(playerid, vehicleid, ispassenger)
{
	if(noveh[playerid]) noveh[playerid] = false;
	return 1;
}

public OnPlayerLeaveDynamicArea(playerid, areaid)		//don't leave spawn area
{
	if(areaid == spawnarea && race[MAX_PLAYERS][1] == 1 && race[playerid][2] == 1)
	{
		SendClientMessage(playerid, 0xFF0000FF, "SERVER: Non lasciare lo spawn della gara.");
		if(floatround(rcp[rid][5][4]) == 0)
		{
			SetPlayerPos(playerid,rcp[rid][MAX_CPS][0],rcp[rid][MAX_CPS][1],rcp[rid][MAX_CPS][2]);		//race spawn
		}
		else
		{
			new Float:zangle;
			zangle = atan2((rcp[rid][0][1] - rcp[rid][MAX_CPS][1]), (rcp[rid][0][0] - rcp[rid][MAX_CPS][0])) - 90.0;
			SetVehicleZAngle(GetPlayerVehicleID(playerid), zangle);		//set vehicle direction towards first cp
			SetVehiclePos(GetPlayerVehicleID(playerid),rcp[rid][MAX_CPS][0],rcp[rid][MAX_CPS][1],rcp[rid][MAX_CPS][2] + 2.0);		//race spawn
			RepairVehicle(GetPlayerVehicleID(playerid));
		}
	}
	return 1;
}