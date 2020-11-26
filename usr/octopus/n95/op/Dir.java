/*
 * Dir.java
 *
 * Creada on 24 de mayo de 2007, 19:30
 *
 * Autor: Sergio de Mingo (sdemingo AT gmail com)
 * Descripcion: Dir en Limbo
 */

package op;

import java.io.*;
import ox.*;

public class Dir implements Enviroment{

    public static String USER="sdemingo";
    
    public String name;
    public String uid;
    public String gid;
    public String muid;
    public Qid qid;
    public int mode;
    public int atime;
    public int mtime;
    public long length;
    public int dtype;
    public int dev;

    private int size;


    public Dir(String n,String u,String g,String mu,Qid q) {
	
	name=n;
        uid=u;
        gid=g;
        muid=mu;
        qid=q;
	if ( (q.qtype&QTDIR)== QTDIR ){ //permisos por defecto
	    int m= Integer.parseInt("755",8);  
	    int md = 1 << 31;  //seteo el bit de directorio. Arreglar
	    mode= m + md;
	}else{
	    mode= Integer.parseInt("644",8); 
	}

        atime= getTime();
        mtime= getTime();
        length=0;
        dtype=85; //tipo del servidor
        dev=0;
    }

    public Dir(Dir cp){
	name=cp.name;
	uid=cp.uid;
	gid=cp.gid;
	muid=cp.muid;
	qid=cp.qid;
	mode=cp.mode;
	atime=cp.atime;
	mtime=cp.mtime;
	length=cp.length;
	dtype=cp.dtype;
	dev=cp.dev;
    }

//REalmente este constructor solo es util si usamos ficheros de verdad
//    public Dir(OFile f,String n){
//	
//	if (n==null)
//	    name=f.getName();
//	else
//	    name=n;
//	
//	uid=USER;
//	gid=USER;
//	muid="";
//	
//	if (f.isDirectory()){
//	    qid=new Qid(QTDIR);
//	    length=0;
//	    int m= Integer.parseInt("755",8); 
//	    int md = 1 << 31;  //seteo el bit de directorio. Arreglar
//	    mode= m + md;
//	    
//	}else{
//	    qid=new Qid(QTFILE);
//	    length=f.length();
//	    mode= Integer.parseInt("644",8);
//	}
//	    
//	atime= (int)f.lastModified();
//        mtime= (int)f.lastModified();
//        dtype=85; //tipo del servidor- pongo el mismo que el inferno
//        dev=0;
//    }

    public static int getTime(){
	return (int)(System.currentTimeMillis() / 1000);
    }
    
    public Dir(byte[] a) {
  
	if (a.length< Enviroment.STATFIXLEN){
	    size=0;
	    return;
	}

	int sz=  (((int)a[1]<<8) | (int)a[0])+ Enviroment.LEN;

	if (a.length < sz){
	   size=0;
	   return;
	}

	//tengo que usar Ophandler.ubyte2int(a[24])<<8 y asi en todos....
	
	this.dtype = ( (int)a[3]<<8) | (int) a[2];
	this.dev =    ((((((int)a[7]<<8)  | (int) a[6])<<8) | (int) a[5])<<8) | (int) a[4];
	
	byte[] qidb=new byte[13]; //len qid
	System.arraycopy(a,8,qidb,0,13);
	//this.qid=new Qid(qidb);
	this.qid =new Qid(a,8);

	this.mode = (((((Ophandler.ubyte2int(a[24])<<8)  | Ophandler.ubyte2int(a[23]))<<8) 
		      | Ophandler.ubyte2int(a[22]))<<8) | Ophandler.ubyte2int(a[21]);

	this.atime = (((((Ophandler.ubyte2int(a[28])<<8)  | Ophandler.ubyte2int(a[27]))<<8) 
		       | Ophandler.ubyte2int(a[26]))<<8) | Ophandler.ubyte2int(a[25]);

	this.mtime = (((((Ophandler.ubyte2int(a[32])<<8)  | Ophandler.ubyte2int(a[31]))<<8) 
		       | Ophandler.ubyte2int(a[30]))<<8) | Ophandler.ubyte2int(a[29]);

	int v0 = (((((Ophandler.ubyte2int(a[36])<<8)  | Ophandler.ubyte2int(a[35]))<<8) 
		   | Ophandler.ubyte2int(a[34]))<<8) | Ophandler.ubyte2int(a[33]);

	int v1 = (((((Ophandler.ubyte2int(a[40])<<8)  | Ophandler.ubyte2int(a[39]))<<8) 
		   | Ophandler.ubyte2int(a[38]))<<8) | Ophandler.ubyte2int(a[37]);

	this.length = ((long)v1<<32) | ((long) v0 & 0xFFFFFFFF);

	int i=41;
	
	try{
	this.name=Ophandler.gstring(a,41);
	i+=this.name.getBytes().length+STR;

	this.uid=Ophandler.gstring(a,i);
	i+=this.uid.getBytes().length+STR;
	
	this.gid=Ophandler.gstring(a,i);
	i+=this.gid.getBytes().length+STR;

	this.muid=Ophandler.gstring(a,i);
	i+=this.muid.getBytes().length+STR;

	}catch(Exception e){
	    e.printStackTrace();
	}
	
	size=sz;
	
    }

    public static Dir unpackdir(byte[] a)
    {
	Dir dir=new Dir(a);

	return dir;

    }

    public byte[] packdir() throws Exception
    {
	int ds=this.packdirsize();
	byte[] a=new byte[ds];
	//size[2]
	a[0]=(byte)(ds-Enviroment.LEN);
	a[1]=(byte)((ds-Enviroment.LEN)>>8);
	//type[2]
	a[2] = (byte) this.dtype;
	a[3] = (byte) (this.dtype>>8);
	//dev[4]
	a[4] = (byte) this.dev;
	a[5] = (byte)(this.dev>>8);
	a[6] = (byte)(this.dev>>16);
	a[7] = (byte)(this.dev>>24);
	//qid.type[1]
	//qid.vers[4]
	//qid.path[8]
	a=this.qid.pack(a,8);
	
	//mode[4]
	a[21] = (byte) this.mode;
	a[22] = (byte) (this.mode>>8);
	a[23] = (byte) (this.mode>>16);
	a[24] = (byte) (this.mode>>24);
	//atime[4]
	a[25] = (byte) this.atime;
	a[26] = (byte) (this.atime>>8);
	a[27] = (byte) (this.atime>>16);
	a[28] = (byte) (this.atime>>24);
	//mtime[4]
	a[29] = (byte) this.mtime;
	a[30] = (byte) (this.mtime>>8);
	a[31] = (byte) (this.mtime>>16);
	a[32] = (byte) (this.mtime>>24);
	//length[8]
	a=Ophandler.p64(a,33,this.length);
	//name[s]
	int i=33+Enviroment.BIT64SZ;
	a=Ophandler.pstring(a,i, this.name);
	i+=this.name.getBytes().length+Enviroment.STR;

	a=Ophandler.pstring(a,i, this.uid);
	i+=this.uid.getBytes().length+Enviroment.STR;

	a=Ophandler.pstring(a,i, this.gid);
	i+=this.gid.getBytes().length+Enviroment.STR;

	a=Ophandler.pstring(a,i, this.muid);
	i+=this.muid.getBytes().length+Enviroment.STR;

	if (i!=a.length)
	    throw new Exception("assertion: Styx->packdir: bad count");

	return a;
    }


    /*
      No deberian ser la misma? probar con ambas
    */
    public int getDirSize(){
	return size;
    }


    public int packdirsize(){
	return Enviroment.STATFIXLEN+name.getBytes().length+uid.getBytes().length+gid.getBytes().length+muid.getBytes().length;
    }


    public String toString()
    {
	String s=new String();
	s=s.concat("["+this.name+" "+this.uid+" "+this.gid+" "+this.qid.toString()+" 0x"+Integer.toOctalString(this.mode)+" "+Integer.toHexString((int)this.length)+" "+Integer.toHexString(this.dtype)+" "+this.dev+"]");
	
	return s;
    }

    public static void printDir(Dir d,byte[] a){
	
	System.out.println ("----Dir de "+d.name+"-----");
	/* Muestro el buffer */
	System.out.println ("size:"+Ophandler.buffer2string(a,0,1,2));
	System.out.println ("type:"+Ophandler.buffer2string(a,2,3,2));
	System.out.println ("dev:"+Ophandler.buffer2string(a,4,7,2));
	System.out.println ("qid.type:"+Ophandler.buffer2string(a,8,8,2));
	System.out.println ("qid.vers:"+Ophandler.buffer2string(a,9,12,2));
	System.out.println ("qid.path:"+Ophandler.buffer2string(a,13,20,2));
	System.out.println ("mode:"+Ophandler.buffer2string(a,21,24,2));
	System.out.println ("atime:"+Ophandler.buffer2string(a,25,28,2));
	System.out.println ("mtime:"+Ophandler.buffer2string(a,29,32,2));
	System.out.println ("length:"+Ophandler.buffer2string(a,33,40,2));

	System.out.println ("name:"+d.name);
	System.out.println ("uid:"+d.uid);
	System.out.println ("gid:"+d.gid);
	System.out.println ("muid:"+d.muid);
    }
    
}
