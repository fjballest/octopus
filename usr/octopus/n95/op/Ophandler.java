/*
 * Ophandler.java
 *
 * Creada on 24 de mayo de 2007, 19:17
 *
 * Autor: Sergio de Mingo (sdemingo AT gmail com)
 * Descripcion:
 */

package op;

import ox.*;

public class Ophandler implements Enviroment{
    
    private static String error="";
   
    
    public Ophandler() { 
        
    }
       
    
    public static byte[] readmsg(Connection fd, int msglim)
    {
        //String error;
        
        if (msglim <=0)
            msglim= MAXHDR + MAXDATA;
        
        byte sbuf[]=new byte[BIT32SZ];
        int n;
        if ((n = fd.readn(sbuf,BIT32SZ))!= BIT32SZ){
            if (n==0){
                return null;
            }
            error="error at Op readmsg";
            return null;
        }
        
        //printBuffer(sbuf,BIT32SZ,2);
        
        int m1;
        m1 =  (ubyte2int(sbuf[1])<<8) | ubyte2int(sbuf[0]) ;
        m1 |= ((ubyte2int(sbuf[3])<<8) | ubyte2int(sbuf[2]))<<16;
        
        if (m1 <= BIT32SZ){
            error="invalid Op message size";
            return null;
        }
        if (m1 > msglim){
            error="Op message longer than agreed: "+m1+" ";
            return null;
        }
        
        byte[] buf2=new byte[m1-BIT32SZ];
  
        if ((n=fd.readn(buf2,m1-BIT32SZ))!=m1-BIT32SZ){
            if (n==0){
                error="Op message trucated";
                return null;
            }
            error= "error at Op readmsg";
            return null;
        }
        
        byte[] buf=new byte[m1];
        System.arraycopy(sbuf,0,buf,0,BIT32SZ); //buf[0:]=sbuf
        System.arraycopy(buf2,0,buf,BIT32SZ,m1-BIT32SZ);
        
        
        return buf;
    }
    
    public static String getError(){
        return error;
    }
    
    
    public static Tmsg unpackTmsg(byte[] buf){
        
        if (buf.length < H)
            return null;
       
	int size= (ubyte2int(buf[1])<<8)    | ubyte2int(buf[0]);
        size|=    (ubyte2int(buf[3])<<8)    | ubyte2int(buf[2])<<16;
        
        if (buf.length != size){
            if (buf.length < size)
                return null;
            System.arraycopy(buf,0,buf,0,size);
        }
        
        int mtype=ubyte2int(buf[4]);
        if (mtype >=TMAX || (mtype&1)==0 || mtype <=0 ){
            System.out.println ("unpack: bad mytpe "+mtype);
            return null;
        }
        
        //int tag = ((int)buf[6]<<8) | (int)buf[5];
	int tag= ( (ubyte2int(buf[6]) <<8) | ubyte2int(buf[5]));
        

	int off,fd,mode,nmsg,count;
	long offset;
	try{
	    switch (mtype){
	    case TREMOVE:
		String path=gstring(buf,H);
		Tremove msg1=new Tremove (tag,path);
		return msg1;
                    
	    case TATTACH:
		off=H;
		String unames = gstring(buf,off);
		off+=unames.getBytes().length+STR;

		String paths = gstring(buf,off);
		off+=paths.getBytes().length+STR;
		//System.out.println ("path:"+paths);
	    
		Tattach msg2 = new Tattach (tag,unames,paths);
		return msg2;
                    
	    case TFLUSH:
		//int oldtag = ((int) buf[H+1]<<8 ) | (int) buf[H];
		int oldtag= ( (ubyte2int(buf[H+1]) <<8) | ubyte2int(buf[H]));
		Tflush msg3 = new Tflush(tag,oldtag);
		return msg3;
                    
	    case TGET:
		off=H;
		String pathget=gstring(buf,H);
		off+=pathget.getBytes().length+STR;
                   
		fd=g16(buf,off);
		off+=BIT16SZ;
                    
		mode=g16(buf,off);
		off+=BIT16SZ;
                    
		nmsg=g16(buf,off);
		off+=BIT16SZ;
                    
		offset=g64(buf, off);
		off+=OFFSET;
                    
		count = g32(buf, off);
		off+=COUNT;
           
		Tget tg=new Tget(tag,pathget,fd,mode,nmsg,offset,count);
		return tg;
	    
	    case TPUT:	    
		off=H;
		String pathput=gstring(buf,H);
		off+=pathput.getBytes().length+STR;
	    
		fd=g16(buf,off);
		off+=BIT16SZ;  

		mode=g16(buf,off);
		off+=BIT16SZ;
	    
		Dir stat=null;
		if ((mode&OSTAT) != 0){
		    int o1;
		    byte[] statb=new byte[buf.length-off];
		    System.arraycopy(buf,off,statb,0,buf.length-off);
		    stat=Dir.unpackdir(statb);
		    off+=stat.getDirSize();
		}

		offset=g64(buf, off);
		off+=OFFSET;

		count = g32(buf, off);
		off+=COUNT;

		byte[] data=new byte[count];
		System.arraycopy(buf,off,data,0,count);

		Tput tp=new Tput(tag,pathput,fd,mode,stat,offset,data);
		return tp;
	    
	    default:
		System.out.println ("No puedo desempaquetar algo que no conozco");
	    
	    }
	}catch(Exception e){
	    System.out.println (e);
	}
        
        return null;
    }
    
    
    public static Rmsg unpackRmsg(byte[] buf){

	if (buf.length < H)
            return null;
        
        int size= (ubyte2int(buf[1])<<8)    | ubyte2int(buf[0]);
        size|=    (ubyte2int(buf[3])<<8)    | ubyte2int(buf[2])<<16;
        
        if (buf.length != size){
            if (buf.length < size)
                return null;
            System.arraycopy(buf,0,buf,0,size);
        }
        
        int mtype=ubyte2int( buf[4]);
        if (mtype >=TMAX || (mtype&1)!=0 || mtype <=0 ){
            System.out.println ("unpack: bad mytpe "+mtype);
            return null;
        }

        //tag =    ( (int) buf[6] << 8 ) | (int)buf[5];
	int tag= ( (ubyte2int(buf[6]) <<8) | ubyte2int(buf[5]));

	int o,fd,mode,count;
	long offset;

	try{
	    switch (mtype){

	    case RERROR:
		return null;
		
	    case RREMOVE:
		Rremove msg1=new Rremove (tag);
		return msg1;
                    
	    case RATTACH:
		
		Rattach msg2 = new Rattach (tag);
		return msg2;
                    
	    case RFLUSH:
		Rflush msg3 = new Rflush(tag);
		return msg3;
                    
	    case RGET:
		o=H;
		Dir stat=null;
		fd=g16(buf,o);
		o+=BIT16SZ;
		mode=g16(buf,o);
		o+=BIT16SZ;
		if ((mode&OSTAT)==OSTAT){
		    int o1;
		    if (buf.length < o + BIT32SZ)
			return new Rreaderror(-1,"short Rget msg");
		    byte[] dirb=new byte[buf.length-o];
		    System.arraycopy(buf,o,dirb,0,buf.length-o);
		    stat=Dir.unpackdir(dirb);
		    o+=stat.getDirSize();
		}
		if (buf.length < o + COUNT)
		    return new Rreaderror(-1,"short Rget msg");
		count=g32(buf,o);
		o+=COUNT;

		if (buf.length < o + count)
		    return new Rreaderror(-1,"short Rget msg");
		byte[]data=new byte[count];
		System.arraycopy(buf,o,data,0,count);
		o+=count;
		
		Rget rg=new Rget(tag,fd,mode,stat,data);
		return rg;
	    
	    case RPUT:	    
		if (buf.length < H + BIT16SZ + COUNT + QID + BIT32SZ)
		    return new Rreaderror(-1,"short Rput msg");
		
		o=H;
		fd=g16(buf,o);
		o+=BIT16SZ;
		count=g32(buf,o);
		o+=COUNT;
		Qid qid=new Qid(buf,o);
		o+=QID;
		int mtime=g32(buf,o);
		o+=BIT32SZ;
		Rput msg4 = new Rput(tag,fd,count,qid,mtime);
		
		return msg4;
	
	    
	    default:
		System.out.println ("No puedo desempaquetar algo que no conozco");
	    
	    }
	}catch(Exception e){
	    e.printStackTrace();
	}

	
        return null;
    }
    
    public int istmsg (byte []f)
    {
        return 0;
    }
    
    
    public int packdirsize (Dir d)
    {
        return 0;
    }
    
    
    public byte[]packdir (Dir d)
    {
        return null;
    }
    
    public int unpackdir(byte[]f)
    {
        return 0;
    }
    
 
    
    public static String mode2text(int m){
        String td="-";
        String ts="-";
        String tc="-";
        String tm="-";
        
        if ( (m & ODATA) !=0)
            td="d";
        if ( (m & OSTAT) !=0)
            ts="s";
        if ( (m & OCREATE) !=0)
            tc="c";
        if ( (m & OMORE) !=0)
            tm="m";
        return td+ts+tc+tm;  
    }


    public static byte[] pstring(byte[]a,int o,String s){

	byte[]sa=s.getBytes();
	
	    
	int n=sa.length;
	a[o]=(byte)n;
	a[o+1]=(byte)(n>>8);
	System.arraycopy(sa,0,a,o+2,n);
	return a;
    }


    public static String gstring (byte[]a, int o) throws Exception{
	if ( (o < 0) || (o+STR > a.length))
            throw new Exception ("gstring: bad offset");
        
        int l= (ubyte2int(a[o+1])<< 8) | ubyte2int( a[o]);
        o+=STR;
        int e=o+l;
        
        if (e > a.length)
	    throw new Exception ("gstring: bad length");

	
	byte[] strb=new byte[e-o];
	System.arraycopy(a,o,strb,0,e-o);
	String s=new String(strb);
        
        return s;  
    }

    
    
    private static int g16(byte[]buf, int i){
        int r=(   ubyte2int( buf[i+1])<<8) | ubyte2int( buf[i]);
        if (r== (int)0xFFFF)
            r = ~0;
        return r;
    }

    private static int g32(byte[]buf, int i){
	
	int r=(((( (ubyte2int( buf[i+3])<<8) | ubyte2int(buf[i+2]))<<8) | ubyte2int( buf[i+1]))<<8) | ubyte2int( buf[i]);

	if (r == (int)0xFFFFFFFF)
	    r = ~0;
	return r;
    }

    private static long g64(byte[]buf, int i){
	int b0=(((((ubyte2int( buf[i+3])<<8) | ubyte2int( buf[i+2]))<<8) | ubyte2int(buf[i+1]))<<8) | ubyte2int( buf[i]);
	
	int b1=(((((ubyte2int( buf[i+7])<<8) | ubyte2int( buf[i+6]))<<8) | ubyte2int(buf[i+5]))<<8) | ubyte2int( buf[i+4]);

	return ((long) b1<<32 | (long) b0 & 0xFFFFFFFF);
    }

    
    public static byte[]p16(byte[]a,int off, int v) {

	a[off] = (byte) v;
	a[off+1]=(byte) (v>>8);

	return a;
    }


    public static byte[]p32(byte[]a,int off, int v) {

	a[off] = (byte) v;
	a[off+1]=(byte) (v>>8);
	a[off+2]=(byte) (v>>16);
	a[off+3]=(byte) (v>>24);
	
	return a;
    }


    
    public static byte[]p64(byte[]buf, int off, long b){
	
	byte[]a=new byte[8];
	
	int i=(int)b;
	a[0]=(byte)i;
	a[1]=(byte)(i>>8);
	a[2]=(byte)(i>>16);
	a[3]=(byte)(i>>24);

	i=(int)(b>>32);
	a[4] = (byte)i;
	a[5]=(byte)(i>>8);
	a[6]=(byte)(i>>16);
	a[7]=(byte)(i>>24);

	System.arraycopy(a,0,buf,off,8);
	return buf;
    }
     
    
    /* 
     * Cambia los byte sin signo de Limbo
     * en enteros de Java. En Java no hay 
     * unsigned bytes!
     */
    public static int ubyte2int(byte b) {
	return (int) b & 0xFF;
    }
    

    //para uso exclusivo de depuracion
    public static String showbinary(int b){
	String bin=Integer.toBinaryString(b);
	return bin;
    }


    public static void printBuffer(byte[]buf,int size,int mode){
        System.out.print ("Buffer: ");
        for (int i=0;i<size;i++){
	    switch(mode){
	    case 0:
		System.out.print(ubyte2int(buf[i])+" ");
		break;
	    case 1:
		System.out.print(Integer.toBinaryString(buf[i])+" ");
		break;
	    case 2:
		System.out.print("0x"+Integer.toHexString(buf[i])+" ");
		break;
	    default:
		break;
	    }
        }
        System.out.println ();
    }


    public static String buffer2string(byte[]buf,int first,int last,int mode){
        String sb="";
	
        for (int i=first;i<=last;i++){
	    switch(mode){
	    case 0://Dec
		sb=sb.concat(ubyte2int(buf[i])+" ");
		break;
	    case 1://Bin
		sb=sb.concat(Integer.toBinaryString(buf[i])+" ");
		break;
	    case 2://Hex
		//System.out.print("0x"+Integer.toHexString(buf[i])+" ");
		sb=sb.concat(Integer.toHexString(buf[i])+" ");
		break;
	    default:
		break;
	    }
        }
	sb=sb.concat("\n");
     
	return sb;
    }
}
