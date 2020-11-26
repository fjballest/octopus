/*
 * AudioSystem.java
 *
 * Creado en 5 de Agosto de 2007, 10:14
 * Descripcion: Sistema para exportar fichero de audio
 */


package dev;

import op.*;
import ox.*;
import java.io.*;
import java.util.*;
import javax.microedition.media.*;
import javax.microedition.media.control.*;


public class AudioSystem implements Dev,Enviroment{
  
    public static final int AUDIOROOTID=1;
    public static final int CTLID =2; //Para control de estado (play,pause,stop) y volumen
    public static final int MIDIID=3;
    public static final int MP3ID =4;
    public static final int AUDIODEVS=5;

    private OSystem osystem;
    private String rootpath;
    private Dir[] files;

    private Player midiplayer;
    private PlayerBuffer midibuffer;
    private Player mp3player;
    private PlayerBuffer mp3buffer;
    private boolean playing;
    private int vol;

    public AudioSystem(OSystem os){	

	osystem=os;
		
	rootpath="/audio";
        files=new Dir[AUDIODEVS];
        
        ///audio
        Qid rootqid=new Qid(QTDIR);
        Dir rootdir=new Dir("audio",Dir.USER,Dir.USER,Dir.USER,rootqid);
        files[AUDIOROOTID]=rootdir;
	osystem.regdev(this,rootdir,OSystem.AUDIODEV);

	///audio/ctl
        Qid ctlqid=new Qid(QTFILE);
        Dir ctldir=new Dir("ctl",Dir.USER,Dir.USER,Dir.USER,ctlqid);
        files[CTLID]=ctldir;
        
        ///audio/midi
        Qid midiqid=new Qid(QTAPPEND|QTFILE);
        Dir mididir=new Dir("midi",Dir.USER,Dir.USER,Dir.USER,midiqid);
        files[MIDIID]=mididir;
        
        ///audio/mp3
        Qid mp3qid=new Qid(QTAPPEND|QTFILE);
        Dir mp3dir=new Dir("mp3",Dir.USER,Dir.USER,Dir.USER,mp3qid);
        files[MP3ID]=mp3dir;
    }


    public int open(String path,int mode){
        
	if (path.equals(rootpath))
            return AUDIOROOTID;
	else if (path.equals(rootpath+"/ctl"))
	    return CTLID;
        else if (path.equals(rootpath+"/midi"))
            return MIDIID;
        else if(path.equals(rootpath+"/mp3"))
            return MP3ID;
        else
            return NULLFD;
    }


    public void disable(){
	
	try{
	    if (midiplayer!=null){
		midiplayer.stop();
		midiplayer.close();
	    }
	}catch(Exception e){
	    OxportMIDlet.addtext(e.toString());
	}
	midibuffer=null;
	midiplayer=null;
    }


    public int create(String path,int mode){
	
        return NULLFD; //no se puede crear
    }


    public boolean remove(String path){

	return false; //no se puede borrar
    }
    
   

    public Dir stat(String path){

	if (path.equals(rootpath))
            return files[AUDIOROOTID];
	else if (path.equals(rootpath+"/ctl"))
	    return files[CTLID];
        else if (path.equals(rootpath+"/midi"))
            return files[MIDIID];
        else if(path.equals(rootpath+"/mp3"))
            return files[MP3ID];
        else
            return null;
    }


    public Dir stat(int fd){
	
	String p=osystem.fd2path(fd);
	return stat(p);
    }
    

    public  int read(int fd, byte[]data,int count, long off){
	

	String p=osystem.fd2path(fd);
	int id=path2id(p);

	switch(id){
	case AUDIOROOTID:
	    int o=0;
            try{
                for (int i=AUDIOROOTID+1;i<AUDIODEVS;i++){
                    byte[] entry=files[i].packdir();
                    System.arraycopy(entry,0,data,o,entry.length);
                    o+=entry.length;
                }
                return o;
            }catch(Exception e){
                return -1;
            }
	case CTLID:
	case MIDIID:
	case MP3ID:
	    return 0;
	default:
	    return -1;
	}
    }



    public int write(int fd,byte[]buf, int count, long off){
	
	/*
	  Notamos que el player de mp3 tiene prioridad sobre el de midi en el 
	  caso de que haya bytes en ambos buffer y se ejecute play teniendo ambos
	  player en reposo. En este caso se ejecuta siempre el mp3player ignorando 
	  el midiplayer.
	*/

	String p=osystem.fd2path(fd);
	int id=path2id(p);
	
	switch (id){
	case MIDIID:
	    
	    if ((count!=0) && (buf!=null)){  
		if (midibuffer!=null)
		    midibuffer.append(buf);
		else
		    midibuffer= new PlayerBuffer(buf);
	    }
	    return buf.length;


	case CTLID:

	    try{
		String c=getCommand(buf);
		if (c.equals("play")){
		    if (playing)
			throw new Exception(); //just player in use
		    
		    if (mp3buffer!=null){
			if (mp3player==null)
			    createmp3player();
			mp3player.start();
			setVolume(1);
			return buf.length;
		    }
		    
		    if (midibuffer!=null){
			if (midiplayer==null)
			    createmidiplayer();
			midiplayer.start();
			setVolume(1);

			return buf.length;
		    }
		    throw new Exception(); //buffers are empty

		}else if (c.equals("stop")){
		    if (mp3player!=null)
			mp3player.stop();

		    if (midiplayer!=null)
			midiplayer.stop();
		    return buf.length;	

		}else if (c.equals("reset")){
		    return -1;
		    // No consigo hacer un reset del player
		    /*if (midiplayer!=null);
			midiplayer.stop();
			
		    if (midibuffer!=null)
			midibuffer.reset();
			
		    if (midiplayer!=null){
			midiplayer.start();
			setVolume(1);
			}*/
		    

		}else if (c.equals("clear")){
		  
		    if (midiplayer!=null)
			midiplayer.close();
		    midiplayer=null;
		    midibuffer=null;

		    if (mp3player!=null)
			mp3player.close();
		    mp3player=null;
		    mp3buffer=null;
		    
		    return buf.length;
		}else 
		    return -1;  
		
	    }catch(Exception e){
		OxportMIDlet.addtext("ERROR in Player control");
		return -1;
	    }
	    
	case MP3ID:

	    if ((count!=0) && (buf!=null)){  
		if (mp3buffer!=null)
		    mp3buffer.append(buf);
		else
		    mp3buffer= new PlayerBuffer(buf);
	    }
	    return buf.length;
	    
	case AUDIOROOTID:
	default:
	    return -1;
	}
    }

    private int path2id(String path){
	if (path.equals(rootpath))
            return AUDIOROOTID;
	else if (path.equals(rootpath+"/ctl"))
	    return CTLID;
        else if (path.equals(rootpath+"/midi"))
            return MIDIID;
        else if(path.equals(rootpath+"/mp3"))
            return MP3ID;
        else
            return NULLFD;
    }



    private void createmidiplayer(){
	try{
	    if (midibuffer!=null)
		midiplayer= Manager.createPlayer((InputStream)midibuffer,"audio/midi");
	    else
		throw new Exception();
	}catch(Exception e){
	    OxportMIDlet.addtext("ERROR: cannot created midi player");
	}
    }


    private void createmp3player(){
	try{
	    if (mp3buffer!=null)
		mp3player= Manager.createPlayer((InputStream)mp3buffer,"audio/mpeg");
	    else
		throw new Exception();
	}catch(Exception e){
	    OxportMIDlet.addtext("ERROR: cannot created mpeg player");
	}
    }


    private String getCommand(byte[] buf){
	
	try{
	    String s=new String(buf);
	    if (s.endsWith("\n"))
		s=s.substring(0,s.length()-1);
	    return s;
	}catch(Exception e){
	    return null;
	}
    }



    private int gVol(byte[] buf){
	
	try{
	    String num=new String(buf);
	    int r=Integer.parseInt(num);
	    System.out.println ("Volumen: "+r);
	    return r;
	}catch(Exception e){
	    return -1;
	}	
    }

    private void setVolume(int newvol){
	try{
	    if ((mp3player!=null)&&(mp3player.getState()!=Player.CLOSED)){
		VolumeControl v=(VolumeControl)mp3player.getControl("VolumeControl");
		if (v!=null)
		    vol=v.setLevel(newvol*10);
	    }
	    
	    if ((midiplayer!=null)&&(midiplayer.getState()!=Player.CLOSED)){
		VolumeControl v=(VolumeControl)midiplayer.getControl("VolumeControl");
		if (v!=null)
		    vol=v.setLevel(newvol*10);
	    }
	}catch(Exception e){
	    OxportMIDlet.addtext("ERROR: cannot update volume"+e.toString());
	}
    }

}
