/*
 * PlayGround.java
 *
 * Created on 15 de octubre de 2007, 16:16
 */
package ox;

import javax.microedition.lcdui.game.*;
import javax.microedition.lcdui.*;
import op.*;

public class PlayGround extends GameCanvas implements CommandListener,Enviroment{
    
    private static final int ARROW_HEIGHT = 50;
    private static final int ARROW_WIDTH = 50;
    private static final int NUM_CORNER_HEIGHT = 50;
    private static final int NUM_CORNER_WIDTH = 50;
    private static final int DELTA = 2;
    private static final int MAGIC_TAG = 3402;
    private static int offtag=0;
    
    private Command backCom;
    private OxportMIDlet midlet;
    private Dir kbdfile;

    private static final int SENSIBILTY = 5;
    private int posx;
    private int posy;
    private int buttons=0;
    private long msec=0;
    
    public PlayGround(OxportMIDlet mid){
	super(false);
	midlet=mid;

	setTitle("PlayGround");
	
	backCom=new Command("Back",Command.SCREEN,1);
	addCommand(backCom);
	setCommandListener(this);

	posx=0;
	posy=0;
	buttons=0;
	msec=0;

	try{
	    int mode=ODATA | OSTAT | OMORE;
	    Tget tstat=new Tget(MAGIC_TAG,"/kbd",-1,mode,4,0,16384);
	    Rget rstat=(Rget)midlet.ox.getOServer().serveget(tstat);
	    kbdfile=rstat.getDir();
	    System.out.println ("Ya hemos pedido el Dir de kdb");
	}catch(Exception e){
	    OxportMIDlet.addtext("Playground need a OServer running");
	}
	
	drawHeader(getGraphics());
	//drawKeyCorner(getGraphics());
    }


    public void keyPressed(int keyCode){
	
	Graphics gp=getGraphics();
	int ac=getGameAction(keyCode);
	
	msec=System.currentTimeMillis();
	
	if (ac == Canvas.UP){
	    posy=posy-SENSIBILTY;
	    sendMsg("m"+posx+" "+posy+" "+buttons+" "+msec+"\n");
	    drawButton(gp,ac,"");
	}

	if (ac == Canvas.RIGHT){
	    posx=posx+SENSIBILTY;
	    sendMsg("m"+posx+" "+posy+" "+buttons+" "+msec+"\n");
	    drawButton(gp,ac,"");
	}

	if (ac == Canvas.LEFT){
	    posx=posx-SENSIBILTY;
	    sendMsg("m"+posx+" "+posy+" "+buttons+" "+msec+"\n");
	    drawButton(gp,ac,"");
	} 

	if (ac == Canvas.DOWN){
	    posy=posy+SENSIBILTY;
	    sendMsg("m"+posx+" "+posy+" "+buttons+" "+msec+"\n");
	    drawButton(gp,ac,"");
	}

	if (ac == Canvas.FIRE){
	    buttons=1;
	    sendMsg("m"+posx+" "+posy+" "+buttons+" "+msec+"\n");
	    drawButton(gp,ac,"");
	    buttons=0;
	}

	if ( (keyCode >=Canvas.KEY_NUM0) && (keyCode<=Canvas.KEY_NUM9)){
	    int key=keyCode-48;   //48 is the keyCode of the key 0.
	    sendMsg("k"+key+" "+msec+"\n");
	    drawButton(gp,ac,Integer.toString(key));
	}

	if (keyCode == Canvas.KEY_STAR){
	    sendMsg("k* "+msec+"\n");
	    drawButton(gp,ac,"*");
	}

	if (keyCode == Canvas.KEY_POUND){
	    sendMsg("k# "+msec+"\n");
	    drawButton(gp,ac,"#");
	}
    }

    public void keyReleased(int keyCode){
	Graphics gp=getGraphics();
	clearScreen(gp);
    }


    
    public void commandAction(Command c, Displayable b){
	if (c == backCom){
	    midlet.exitPlay();
	}
    }



    private void drawHeader(Graphics g){
	int px= 10;
	int py= 10;

	Font f=Font.getFont(Font.FACE_SYSTEM,Font.STYLE_BOLD, Font.SIZE_LARGE);
	g.setFont(f);
	g.setColor(0,0,0);  //negro
	g.drawString("PlayGround", px, py, Graphics.TOP | Graphics.LEFT);
	flushGraphics();
	g.setFont(null);
    }

    private void drawKeyCorner(Graphics g){
	
	int px= getWidth()-NUM_CORNER_WIDTH;
	int py= getHeight()-NUM_CORNER_HEIGHT;

	g.setColor(0,0,0);  //negro
	g.fillRect(px,py,NUM_CORNER_WIDTH ,NUM_CORNER_HEIGHT );

	g.setColor(255,255,255);  //negro
	g.fillRect(px+DELTA,py+DELTA,NUM_CORNER_WIDTH-DELTA ,NUM_CORNER_HEIGHT-DELTA );
	flushGraphics();
    }

    
    private void drawButton(Graphics g, int type, String label){
	
	int px= (getWidth()/2)-(ARROW_WIDTH/2);
	int py= (getHeight()/2)-(ARROW_HEIGHT/2);

	int p1_x=getWidth()/2;         //middle ground top. Coord x.
	int p1_y=py;                   //middle ground top. Coord y.

	int p2_x=px;                   //middle ground left. Coord x.
	int p2_y=getHeight()/2;        //middle ground left. Coord y.

	int p3_x=getWidth()/2;         //middle ground bottom. Coord x.
	int p3_y=(getHeight()/2)+(ARROW_HEIGHT/2);  //middle ground bottom. Coord y.

	int p4_x= px+ARROW_WIDTH;       //middle ground right. Coord x.
	int p4_y= getHeight()/2;        //middle ground right. Coord y.

	


	g.setColor(0,0,0);  //negro
	g.fillRect(px-DELTA,py-DELTA, ARROW_WIDTH+DELTA, ARROW_HEIGHT+DELTA);
	g.setColor(128,128,128);  //gris
	g.fillRect(px,py, ARROW_WIDTH-DELTA, ARROW_HEIGHT-DELTA);

	
	switch(type){
	case Canvas.LEFT:
	    g.setColor(0,0,0);  //negro
	    g.fillTriangle(p1_x,p1_y,p2_x,p2_y,p3_x,p3_y);
	    break;
	    
	case Canvas.RIGHT:
	    g.setColor(0,0,0);  //negro
	    g.fillTriangle(p1_x,p1_y,p4_x,p4_y,p3_x,p3_y);
	    break;
	    
	case Canvas.UP:
	    g.setColor(0,0,0);  //negro
	    g.fillTriangle(p2_x,p2_y,p4_x,p4_y,p1_x,p1_y);
	    break;

	case Canvas.DOWN:
	    g.setColor(0,0,0);  //negro
	    g.fillTriangle(p2_x,p2_y,p4_x,p4_y,p3_x,p3_y);
	    break;

	case Canvas.FIRE:
	    g.setColor(0,0,0);  //negro
	    g.fillTriangle(p2_x,p2_y,p4_x,p4_y,p3_x,p3_y);
	    g.fillTriangle(p2_x,p2_y,p4_x,p4_y,p1_x,p1_y);
	    break;
	    
	default:
	    //draw label
	    int ptx=px+10;
	    int pty=py+10;
	    Font f=Font.getFont(Font.FACE_SYSTEM,Font.STYLE_BOLD, Font.SIZE_LARGE);
	    g.setFont(f);
	    g.setColor(0,0,0);  //negro
	    g.drawString(label, ptx, pty, Graphics.TOP | Graphics.LEFT);
	    g.setFont(null);
	}
		
	flushGraphics();
    }



    private void clearScreen(Graphics g){
	int px= (getWidth()/2)-(ARROW_WIDTH/2);
	int py= (getHeight()/2)-(ARROW_HEIGHT/2);
	
	g.setColor(255,255,255);
	g.fillRect(px-DELTA,py-DELTA, ARROW_WIDTH+DELTA, ARROW_HEIGHT+DELTA);

	flushGraphics();
    }


    private void sendMsg(String text){
	byte[] textb=new byte[text.length()+STR];
	textb=Ophandler.pstring(textb,0,text);
	
	try{
	    int mode=ODATA | OSTAT | OMORE;
	    Tput tput=new Tput(MAGIC_TAG+offtag,"/kbd",-1,mode,kbdfile,textb.length,textb);
	    offtag++;
	    Rput rput=(Rput)midlet.ox.getOServer().serveput(tput);
	}catch(Exception e){
	    OxportMIDlet.addtext("Playground need a OServer running");
	}
    }
}



