/*
 * KbdSystem.java
 *
 * Creado en 25 de septiembre de 2007, 10:14
 * Descripcion: 
 */


package dev;

import javax.microedition.pim.*;
import java.util.*;
import java.io.*;
import op.*;
import ox.*;


public class KbdSystem implements Dev,Enviroment{
  
    public static final int KBDDEVS = 1;
    public static final int KBDID = 0;
    private static final int MAX_EVENTS = 500;

    private OSystem osystem;
    private String rootpath;
    private Dir[] files;

    private EventQueue queue;

    public KbdSystem(OSystem os){	

	osystem=os;
	
	rootpath="/kbd";
        files=new Dir[KBDDEVS];

	Qid kbdqid=new Qid(QTFILE);
        Dir kbddir=new Dir("kbd",Dir.USER,Dir.USER,Dir.USER,kbdqid);
	files[KBDID]=kbddir;
	osystem.regdev(this,kbddir,OSystem.KBDDEV);

	queue=new EventQueue();
    }

    public void disable(){

    }

    
    public int open(String path,int mode){
        
	if (path.equals(rootpath))
	    return KBDID;
	else
            return NULLFD;
    }

    public int create(String path,int mode){
	
        return NULLFD; //no se puede crear
    }


    public boolean remove(String path){

	return false; //no se puede borrar
    }
    
   

    public Dir stat(String path){
    
	if (path.equals(rootpath))
	    return files[KBDID];
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
	case KBDID:
	    String s;
	    byte[] aux=new byte[count];
	    int btpacked=0;
	    do{
		s=queue.get();
		//System.out.println ("Enviamos el evento: "+s);
		if (s==null)
		    return btpacked;
		byte [] strb=s.getBytes();
		System.arraycopy(strb,0,data,btpacked,s.getBytes().length);
		btpacked=btpacked+s.getBytes().length;
		
	    }while (btpacked==count);
	    
	    return btpacked;
	    
	default:
	    return -1;
	}
    }


    public int write(int fd,byte[]buf, int count, long off){

	String p=osystem.fd2path(fd);
	int id=path2id(p);
	switch(id){
	case KBDID:
	   
	    try{
		String str=Ophandler.gstring(buf,0);
		//System.out.println ("Almacenamos el siguiente evento: "+str);
		queue.put(str);
	    }catch(Exception e){
		return -1;
	    }
	    return 0;
	default:
	    return -1;
	}
	

    }


    private int path2id(String path){
	if (path.equals(rootpath))
	    return KBDID;
	else 
            return NULLFD;
    }




	
}
