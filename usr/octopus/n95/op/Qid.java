/*
 * Qid.java
 *
 * Creada on 24 de mayo de 2007, 19:24
 *
 * Autor: Sergio de Mingo (sdemingo AT gmail com)
 * Descripcion: Qid de fichero Inferno
 */

package op;

public class Qid {
   
    public static long qpath=10;
    
    public long path;  //big en limbo (64bits)   //8Bytes
    public int vers;                             //4Bytes
    public int qtype;                            //1Byte

    //private int size;
    

    public Qid(int qt) {
	
	path=qpath++;
	vers=Dir.getTime();
	qtype=qt;
    }
    public Qid(byte[] f,int off) 
    {
        path=0;
        vers=0;
        qtype=0;

	int i=off;
	qtype=Ophandler.ubyte2int(f[i]);
	vers=  (((((Ophandler.ubyte2int(f[i+4])<<8) | Ophandler.ubyte2int(f[i+3]))<<8)  
		 | Ophandler.ubyte2int(f[i+2]))<<8)  |  Ophandler.ubyte2int(f[i+1]);
	
	i+=Enviroment.BIT8SZ + Enviroment.BIT32SZ;

	int path0= (((((Ophandler.ubyte2int(f[i+3]) <<8) | Ophandler.ubyte2int(f[i+2]))<<8 )  
		     | Ophandler.ubyte2int(f[i+1]))<<8) | Ophandler.ubyte2int(f[i]);
	i+=Enviroment.BIT32SZ;

	int path1= (((((Ophandler.ubyte2int(f[i+3]) <<8) | Ophandler.ubyte2int(f[i+2]))<<8 )  
		     | Ophandler.ubyte2int(f[i+1]))<<8) | Ophandler.ubyte2int(f[i]);

	path= ((long)path1<<32) | ((long)path0 & 0xFFFFFFFF);
	
	//size=i;
    }
    

    public byte[] pack(byte[]a,int off)
    {
	byte[] buf=new byte[13];
	buf[0]= (byte)this.qtype;
	
	int v=this.vers;
	buf[1] = (byte)v;
	buf[2] = (byte)(v>>8);
	buf[3] = (byte)(v>>16);
	buf[4] = (byte)(v>>24);
	
	v=(int)this.path;
	buf[5] = (byte)v;
	buf[6] = (byte)(v>>8);
	buf[7] = (byte)(v>>16);
	buf[8] = (byte)(v>>24);

	v=(int) (this.path >>32);
	buf[9] = (byte)v;
	buf[10] = (byte)(v>>8);
	buf[11] = (byte)(v>>16);
	buf[12] = (byte)(v>>24);

	System.arraycopy(buf,0,a,off,13);
	return a;
    }


    public String toString(){
	String s="(0x"+Integer.toHexString((int)this.path)+" "+this.vers+" 0x"+Integer.toHexString(this.qtype)+")";
	return s;
    }
}

