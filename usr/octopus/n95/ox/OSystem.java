/*
 * OSystem.java
 *
 * Creado en 5 de Agosto de 2007, 10:14
 * Descripcion: Sistema para exportar dispositivos del telefono
 */


package ox;

import op.*;
import dev.*;
import java.io.*;
import java.util.*;
import javax.microedition.media.*;
import javax.microedition.media.control.*;


/* 
 * Para añadir un nuevo dispositivo:
     - Incluir una nueva constante de dispositivo
     - Añadirlo en la función devid()
     - Construirlo y arrancarlo en el objeto OServer
*/

public class OSystem implements Enviroment{
  
    public static final int DEVS=500;
    public static final int UNKNOWDEV=-1;

    /* Lista de dispositivos soportados*/
    public static final int ROOT=0;
    public static final int AUDIODEV=1;
    public static final int CONTACTDEV=2;
    public static final int KBDDEV=3;
    public static final int FILEDEV=4;
    public static final int MSGDEV=5;
    

    private String rootpath;
    private Dir[] stats; 
    private Dev[] devs;
    private int ndevs=0;
    private String[] fdtable;
    private int nfds;

    public OSystem(){

	rootpath="/";
	stats=new Dir[DEVS];
	devs=new Dev[DEVS];
	fdtable=new String[DEVS]; //max num devs
	nfds=0;
	
	//raiz del arbol
        Qid rootqid=new Qid(2001);
        Dir rootdir=new Dir(rootpath,Dir.USER,Dir.USER,Dir.USER,rootqid);
        stats[0]=rootdir;
	
	ndevs++;
    }

    public void abort(){
	for (int i=ROOT+1;i<ndevs;i++)
	    if (devs[i]!=null)
		devs[i].disable();
    }

    public void regdev(Dev dev,Dir stat,int n){  //metodo para registrar dispositivos
	stats[n]=stat;
	devs[n]=dev;
	ndevs++;
    }


    public int open(String path,int mode){

	for (int i=0;i<nfds;i++)
	    if ( (fdtable[i]!=null) && (fdtable[i].equals(path)==true))
		return i; //lo hemos encontrado
	
	//no lo hemos encontramos asi que lo alojamos
	int l=lastfd();
	fdtable[l]=path;
	nfds++;

	int id=devid(path);
	if (id==ROOT)
	    return l;
	
	if (id!=UNKNOWDEV)
	    devs[id].open(path,mode);

	return l;
    }

    public int create(String path,int mode){
	
        return NULLFD; //no se puede crear
    }


    public boolean remove(String path){

	return false; //no se puede borrar por ahora
    }
    
   

    public Dir stat(String path){
	

	int id=devid(path);
	
	if (id==ROOT)
	    return stats[ROOT];
	
	if (id!=UNKNOWDEV)
	    return devs[id].stat(path);
	else
	    return null;
    }


    public Dir stat(int fd){
	
	String path=fd2path(fd);
	return stat(path);
    }
    

    public  int read(int fd, byte[]data,int count, long off){
	

	String path=fd2path(fd);
	int id=devid(path);

	if (id==ROOT){
	    int o=0;
            try{
                for (int i=ROOT+1;i<stats.length;i++){
		    if (stats[i]!=null){
			byte[] entry=stats[i].packdir();
			System.arraycopy(entry,0,data,o,entry.length);
			o+=entry.length;
		    }
                }
                return o;
            }catch(Exception e){
                return -1;
            }
	}

	if (id!=UNKNOWDEV){
	    byte[] b=new byte[data.length];
	    int l=devs[id].read(fd,b,count,off);
	    System.arraycopy(b,0,data,0,l);
	    return l;
	}else
	    return -1;
    }

    public int write(int fd,byte[]buf, int count, long off){
	
	String path=fd2path(fd);
	int id=devid(path);

	if (id==ROOT)
	    return -1;
	
	if (id!=UNKNOWDEV)
	    return devs[id].write(fd,buf,count,off);
	else
	    return -1;
    }


    public String fd2path(int fd){
	if (fd>=0)
	    return fdtable[fd];
	else
	    return null;
    }

    /* Devuelve el identificador de dispositivo a quien pertenece ese path*/
    private int devid(String path){
	
	/*
	  NOTA: Deberia sacar los nombres de los path de cada una de las clases. 
	  Quizas guardandolos en ellas como constantes estaticas publicas
	 */
	if (path!=null){
	    if (path.equals("/"))
		return ROOT;
	    else if (path.indexOf("/audio")==0)
		return AUDIODEV;
	    else if (path.indexOf("/contacts")==0)
		return CONTACTDEV;
	    else if (path.indexOf("/kbd")==0)
		return KBDDEV;
	    else if (path.indexOf("/files")==0)
		return FILEDEV;
	    else if (path.indexOf("/sms")==0)
		return MSGDEV;
	    else
		return UNKNOWDEV;
	}else
	    return UNKNOWDEV;
    }

    

    
    private int lastfd(){
	
	if (fdtable[0]==null)
	    return 0;
	int i=0;	
	for (i=0;i<nfds;i++)
	    if (fdtable[i]==null)
		return i;

	return i;
    }
}
