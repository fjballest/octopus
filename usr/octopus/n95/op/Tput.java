/*
 * Tput.java
 *
 * Creada on 27 de mayo de 2007, 20:26
 *
 * Autor: Sergio de Mingo (sdemingo AT gmail com)
 * Descripcion:
 */

package op;

public class Tput extends Tmsg implements Enviroment{
    
    private String path;
    private int fd;
    private int mode;
    private Dir stat;
    private long offset;
    private byte[] data;
    
    public Tput(int t,String p,int f,int m,Dir s, long o,byte[] d) {
        super(t,TPUT);
	path=p;
	fd=f;
	mode=m;
	stat=s;
	offset=o;
	data=d;
    }
    
    public int packesize(){
        int m1=H;
        
        m1 += STR + path.getBytes().length;
        m1 += BIT16SZ;
        m1 += BIT16SZ;
	if ((this.mode&OSTAT)==OSTAT)
	    m1+= this.stat.packdirsize();
        m1 += OFFSET;
        m1 += COUNT;
	m1 += this.data.length;
        
        return m1;
    }
    
    public byte[] pack(){
        
	int ps=this.packesize();

        byte []buf=super.packhdr(ps);
	int off=H;

	buf=Ophandler.pstring(buf,off,this.path);
	off+=STR + path.getBytes().length;
	buf=Ophandler.p16(buf,off,this.fd);
	off+=BIT16SZ;
	buf=Ophandler.p16(buf,off,this.mode);
	off+=BIT16SZ;
	try{
	    if ((this.mode&OSTAT) != 0){
		byte[] statb=this.stat.packdir();
		int n=statb.length;
		System.arraycopy(statb,0,buf,off,n);
		off+=n;
	    }
	}catch(Exception e){
	    System.out.println ("Tput.pack:"+e);
	}
	buf=Ophandler.p64(buf,off,this.offset);
	off+=OFFSET;
	buf=Ophandler.p32(buf,off,this.data.length);
	off+=COUNT;
	System.arraycopy(this.data,0,buf,off,this.data.length);
       
        
        return buf;
    }
    

    public String text(){
	String datas=new String(data);
	
        String s="Tput "+this.tag +" ["+this.path+"] fd="+this.fd+" mode="+Ophandler.mode2text(this.mode)+" offset="+offset; //+" data="+datas;

	if ((this.mode&OSTAT) != 0)
	    s=s.concat(" "+stat.toString());

	
        return s;
    }
    
    public int mtype(){
        return this.ttype;
    }
    


    public byte[] getData(){
	return data;
    }


    public String getPath(){
	return path;
    }

    public int getMode(){
	return mode;
    }

    public Dir getStat(){
	return stat;
    }

    public int getFd(){
	return fd;
    }

    public long getOffset(){
	return offset;
    }
}
