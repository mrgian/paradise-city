//Sincronizza l'ora dei giocatori con l'ora del server (ora reale)

#include <a_samp>

new Text:txtTimeDisp;
new hour, minute;
new timestr[32];

forward UpdateTime();

public UpdateTime()
{
    gettime(hour, minute);

   	format(timestr,32,"%02d:%02d",hour,minute);
   	TextDrawSetString(txtTimeDisp,timestr);
   	SetWorldTime(hour);
   	
	new x=0;
	while(x!=MAX_PLAYERS) {
	    if(IsPlayerConnected(x) && GetPlayerState(x) != PLAYER_STATE_NONE) {
	        SetPlayerTime(x,hour,minute);
		}
		x++;
	}
}

public OnGameModeInit()
{
	// Init our text display
	txtTimeDisp = TextDrawCreate(620.0,20.0,"00:00");
	TextDrawUseBox(txtTimeDisp, 0);
	TextDrawFont(txtTimeDisp, 3);
	TextDrawSetShadow(txtTimeDisp,0); // no shadow
    TextDrawSetOutline(txtTimeDisp,2); // thickness 1
    TextDrawBackgroundColor(txtTimeDisp,0x000000FF);
    TextDrawColor(txtTimeDisp,0xFFFFFFFF);
    TextDrawAlignment(txtTimeDisp,3);
	TextDrawLetterSize(txtTimeDisp,0.4,1.6);
	
	UpdateTime();
	SetTimer("UpdateTime",1000 * 60,1);

	return 1;
}

public OnPlayerSpawn(playerid)
{
	TextDrawShowForPlayer(playerid,txtTimeDisp);	
    gettime(hour, minute);
	SetPlayerTime(playerid,hour,minute);
	
	return 1;
}

public OnPlayerDeath(playerid, killerid, reason)
{
    TextDrawHideForPlayer(playerid,txtTimeDisp);
 	return 1;
}

public OnPlayerConnect(playerid)
{
    gettime(hour, minute);
    SetPlayerTime(playerid,hour,minute);
    return 1;
}
