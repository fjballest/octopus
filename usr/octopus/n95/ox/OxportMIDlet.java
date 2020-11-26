/*
 * OxportMIDlet.java
 *
 * Created on 5 de agosto de 2007, 16:16
 */
package ox;

import javax.microedition.midlet.*;
import javax.microedition.lcdui.*;
import javax.microedition.media.*;
import java.io.*;

/**
 *
 * @author  sdemingo
 * @version
 */

public class OxportMIDlet extends MIDlet implements CommandListener{
    private Command exitCom, initCom,playCom;
    private Display display;
    public static TextBox textBox;
    public static PlayGround playground;
    public static Oxport ox;
  
    
    public OxportMIDlet(){
        display=Display.getDisplay(this);
        exitCom=new Command("Exit",Command.EXIT,2);
	initCom=new Command("Export", Command.SCREEN,1);
	playCom=new Command("PlayGround", Command.SCREEN,1);
        
    }
    
    public void startApp() {
        textBox=new TextBox("Ophone","\n",512, TextField.UNEDITABLE);
	OxportMIDlet.addtext("Listo para exportar servicios...");
	textBox.addCommand(exitCom);
	textBox.addCommand(playCom);
	textBox.addCommand(initCom);
	textBox.setCommandListener(this);
	display.setCurrent(textBox);
    }
    
    public void pauseApp(){
    }
    
    public void destroyApp(boolean unconditional){
	if (ox!=null)
	    ox.exitOxport();
    }
    
    public void commandAction(Command c, Displayable s){
        if (c == exitCom){
	    destroyApp(true);
            notifyDestroyed();

        }else if ( c == initCom){
	    if (ox==null){
		textBox.insert("Exportando...\n",textBox.size());
		ox=new Oxport();
		ox.start();
	    }
        }else if ( c == playCom){
	    if (( ox == null) || (ox.getOServer() == null))
		addtext("Playground need a OServer running");
	    else{
		if (playground == null)
		    playground=new PlayGround(this);
		display.setCurrent(playground);
	    }
	}else{
	}
    }

  
    public static void addtext(String text){
	if (textBox!=null)
	    textBox.insert(text+"\n",textBox.size());
    }

    public void exitPlay(){
	display.setCurrent(textBox);
    }
  
}
