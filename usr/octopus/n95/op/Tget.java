/*
 * Tget.java
 *
 * Creada on 27 de mayo de 2007, 20:26
 *
 * Autor: Sergio de Mingo (sdemingo AT gmail com)
 * Descripcion:
 */

package op;

public class Tget extends Tmsg implements Enviroment{
    
    private String path;
    private int fd;
    private int mode;
    private int nmsgs;
    private long offset;
    private int count;
    
    public Tget(int t,String p,int f,int m,int n, long o,int c) {
        super(t,TGET);
	path=p;
	fd=f;
	mode=m;
	nmsgs=n;
	offset=o;
	count=c;
    }
    
    public int packesize(){
        int m1=H;
        
        m1 += STR + path.getBytes().length;
        m1 += BIT16SZ;
        m1 += BIT16SZ;
        m1 += BIT16SZ;
        m1 += OFFSET;
        m1 += COUNT;
        
        return m1;
    }
    
    public byte[] pack(){
        
        int ps=this.packesize();

        byte []buf=super.packhdr(ps);
	int off=H;
	buf=Ophandler.pstring(buf,off,this.path);
	off+=STR+this.path.getBytes().length;
	buf=Ophandler.p16(buf,off,this.fd);
	off+=BIT16SZ;
	buf=Ophandler.p16(buf,off,this.mode);
	off+=BIT16SZ;
	buf=Ophandler.p16(buf,off,this.nmsgs);
	off+=BIT16SZ;
	buf=Ophandler.p64(buf,off,this.offset);
	off+=OFFSET;
	buf=Ophandler.p32(buf,off,this.count);
	off+=COUNT;
	
        return buf;
    }
    
    public String text(){
        String s="Tget "+this.tag +" ["+this.path+"] fd="+this.fd+" mode="+Ophandler.mode2text(this.mode)+" n="+this.nmsgs+" o="+this.offset+" c="+this.count;
        return s;
    }
    
    public int mtype(){
        return this.ttype;
    }


    public int getMode(){
	return mode;
    }

    public String getPath(){
	return path;
    }

    public int getFd(){
	return fd;
    }

    public long getOffset(){
	return offset;
    }

    public int getCount(){
	return count;
    }
    

    public int getNmsg(){
	return nmsgs;
    }
}
