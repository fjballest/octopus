/*
 * FileSystem.java
 *
 * Creado en 29 de septiembre de 2007, 10:14
 * Descripcion: 
 */


package dev;

import javax.microedition.io.file.*;
import javax.microedition.io.*;
import java.util.*;
import java.io.*;
import op.*;
import ox.*;


public class FileSystem implements Dev,Enviroment{
  
    public static final int FILEDEVS=1;
    public static final int FILEROOTID=0;


    private OSystem osystem;
    private String rootpath;
    private Dir[] files;
    

    public FileSystem(OSystem os){	

	osystem=os;
	
	rootpath="/files";
        files=new Dir[FILEDEVS];

        Qid rootqid=new Qid(QTDIR);
        Dir rootdir=new Dir("files",Dir.USER,Dir.USER,Dir.USER,rootqid);
        files[FILEROOTID]=rootdir;
	osystem.regdev(this,rootdir,OSystem.FILEDEV);
    }

    public void disable(){

    }

    
    public int open(String path,int mode){
        
	if (path.equals(rootpath))
	    return FILEROOTID;
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
	    return files[FILEROOTID];
	else {
	    String phonepath = getPhonePath(path);
	    try{
		FileConnection fc = (FileConnection)Connector.open("file:///" + phonepath);
		
		if (!fc.exists())
		    return null;
	
		String name=getName(fc);	
		Qid pathqid;
	    		    
		if (fc.isDirectory()){
		    pathqid=new Qid(QTDIR);
		}else{
		    pathqid=new Qid(QTFILE);
		}
		Dir pathdir=new Dir(name,Dir.USER,Dir.USER,Dir.USER,pathqid);
		return pathdir;
	    }catch(Exception e){
		OxportMIDlet.addtext("ERROR cannot stat "+path);
		return null;
	    }
        }
    }


    public Dir stat(int fd){
	
	String p=osystem.fd2path(fd);
	return stat(p);
    }
    

    public int read(int fd, byte[]data,int count, long off){
	
	String p=osystem.fd2path(fd);
	int id=path2id(p);
 
	switch(id){
	case FILEROOTID:
	    int o=0;
            try{
		Enumeration e = FileSystemRegistry.listRoots();
		while (e.hasMoreElements()) {
		    String phonepath = (String) e.nextElement();
		    Dir pathdir=stat(rootpath+"/"+phonepath);
		    byte[] entry=pathdir.packdir();
		    System.arraycopy(entry,0,data,o,entry.length);
                    o+=entry.length;
		} 		
                return o;

            }catch(Exception e){
                return -1;
	    }

	case NULLFD: 
	    /*
	      No es un fichero propio del dispositivo sino que puede
	      estar en la tarjeta
	     */
	    String phonepath = getPhonePath(p);
	    try{
		FileConnection fc = (FileConnection)Connector.open("file:///" + phonepath);
		
		if (!fc.exists())
		    return -1;
		
		if (fc.isDirectory()){
		    o=readDirectory(fc,data);
		}else{
		    if (!fc.canRead())
			return -1;
	
		    DataInputStream in=fc.openDataInputStream();
		    try{
			o=in.read(data,(int)off,count);
		    }catch(Exception e){
			return 0;
		    }
		}
	     
		return o;
		    
	    }catch(Exception e){
		OxportMIDlet.addtext("ERROR cannot read "+phonepath);
		return -1;
	    }
	default:
	    return -1;
	}
    }


    public int write(int fd,byte[]buf, int count, long off){

	String p=osystem.fd2path(fd);
	int id=path2id(p);
	
	return -1;
    }


    private int path2id(String path){
	if (path.equals(rootpath))
	    return FILEROOTID;
	else 
            return NULLFD;
    }



    private String getPhonePath(String path){
	
	if (!path.endsWith("/"))
	    path=path.concat("/");
		   
	String pp=path.substring(rootpath.length()+1,path.length());
	return pp;
    }
    

    private int readDirectory(FileConnection f,byte[] data){
	byte[] d=new byte[data.length];
	try{
	    Enumeration e = f.list();
	    int o=0;
	    while (e.hasMoreElements()) {
		String p = (String) e.nextElement();	    
		Dir pathdir=stat(rootpath+f.getPath()+p);
		if (pathdir==null)
		    throw new Exception();
		byte[] entry=pathdir.packdir();
		System.arraycopy(entry,0,d,o,entry.length);
		o+=entry.length;
	    }

	    System.arraycopy(d,0,data,0,o);
	    return o;
	}catch(Exception e){
	    return -1;
	}
    }


    private String getName(FileConnection fc){
	
	String name;
	
	name=fc.getName();
	if (name.length()!=0){
	    if (name.endsWith("/")) //si termina en /
		name = name.substring(0,name.length()-1); //se la quitamos	
	    return name;
	}
	
	name = fc.getPath();
	if (name.endsWith("/")) //si termina en /
	    name = name.substring(0,name.length()-1); //se la quitamos	
	name=name.substring(name.lastIndexOf('/')+1,name.length());
	return name;
    }

}
