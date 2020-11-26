/*
 * MsgSystem.java
 *
 * Creado en 25 de octubre de 2007, 10:14
 * Descripcion: 
 */


package dev;

import javax.microedition.io.*;
import javax.wireless.messaging.*;
import java.util.*;
import java.io.*;
import op.*;
import ox.*;


public class MsgSystem implements Dev,Enviroment{
  
    public static final int MSGDEVS = 1;
    public static final int MSGID = 0;

    public static final int MAX_SMS_SIZE = 150;

    private OSystem osystem;
    private String rootpath;
    private Dir[] files;


    public MsgSystem(OSystem os){	

	osystem=os;
	
	rootpath="/sms";
        files=new Dir[MSGDEVS];

	Qid msgqid=new Qid(QTFILE);
        Dir msgdir=new Dir("sms",Dir.USER,Dir.USER,Dir.USER,msgqid);
	files[MSGID]=msgdir;
	osystem.regdev(this,msgdir,OSystem.MSGDEV);
    }

    public void disable(){

    }

    
    public int open(String path,int mode){
        
	if (path.equals(rootpath))
	    return MSGID;
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
	    return files[MSGID];
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

	return 0;
    }


    public int write(int fd,byte[]buf, int count, long off){

	String p=osystem.fd2path(fd);
	int id=path2id(p);

	switch(id){
	case MSGID:
	    try{
		//formato de la escritura <num>:<mensaje>
		String msg=new String(buf);
		if (msg.indexOf(":")<0)
		    throw new Exception();
	
		String num=msg.substring(0,msg.indexOf(":"));	

		if (!checkPhoneNum(num))
		    throw new Exception("bad format of phone number");
		    
		String content=msg.substring(msg.indexOf(":")+1,msg.length());
		if (content.length()>MAX_SMS_SIZE)
		    content=content.substring(0,MAX_SMS_SIZE);

		String address="sms://"+num;
		MessageConnection smsconn = null;
	
		smsconn = (MessageConnection)Connector.open(address);
		TextMessage mtxt=
		    (TextMessage)smsconn.newMessage(MessageConnection.TEXT_MESSAGE);
		mtxt.setPayloadText(content);
		smsconn.send(mtxt);
		smsconn.close();
		
		//OxportMIDlet.addtext("sms sending");
		return count;
		
	    }catch(Exception e){
		System.out.println (e);
		OxportMIDlet.addtext("sms cannot be sending");
		return -1;
	    }
	default:
	    return -1;
	}
    }


    private int path2id(String path){
	if (path.equals(rootpath))
	    return MSGID;
	else 
            return NULLFD;
    }



    private boolean checkPhoneNum(String n){
	
	System.out.println ("checknum:["+n+"]");
	
	if ( (n.length()<9) || (n.length()>12))
	    return false;
	
	try{
	    long l=Long.parseLong(n);
	}catch(Exception e){
	    return false;
	}
	return true;
    }
	
}
