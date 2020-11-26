/*
 * Rget.java
 *
 * Creada on 23 de Junio de 2007, 20:26
 *
 * Autor: Sergio de Mingo (sdemingo AT gmail com)
 * Descripcion:
 */

package op;

public class Rget extends Rmsg implements Enviroment{
    
    private int fd;
    private int mode;
    private Dir stat;
    private byte[] data;
    
    public Rget(int t,int f,int m,Dir s, byte[] d) {
        super(t,RGET);
	fd=f;
	mode=m;
	stat=s;
	data=d;
	
    }
    
    public int packesize(){
        int m1=H;
        
        m1 += BIT16SZ;
        m1 += BIT16SZ;
        if ((this.mode&OSTAT) == OSTAT)
	    m1+=this.stat.packdirsize();
        m1 += BIT32SZ;
	m1 += this.data.length;
        
        return m1;
    }
    
    public byte[] pack(){
        
	int ps=this.packesize();
        byte []buf=super.packhdr(ps);
       
	int o=H;
	buf=Ophandler.p16(buf,o,this.fd);
	o+=BIT16SZ;

	buf=Ophandler.p16(buf,o,this.mode);
        o+=BIT16SZ;

	try{
	    if ((this.mode&OSTAT) == OSTAT){
		byte[] statb=this.stat.packdir();
		int n=statb.length;
		System.arraycopy(statb,0,buf,o,n);
		o+=n;
	    }
	}catch(Exception e){
	    System.out.println (e);
	}

	buf=Ophandler.p32(buf,o,data.length);
	o+=COUNT;
	System.arraycopy(data,0,buf,o,data.length);
	
        return buf;
    }
    
    public String text(){
        String s="Rget "+this.tag +" fd="+this.fd+" mode="+Ophandler.mode2text(this.mode);
	if ((this.mode&OSTAT)==OSTAT)
	    s=s.concat(" "+this.stat.toString());

	String dat=new String(this.data);
	s=s.concat(" "+this.data.length+" ");
	if (dat.length()>10)
	    s=s.concat(" "+dat.substring(0,10)+"...");
	else
	    s=s.concat(" "+dat);
	
	
        return s;
    }
    
    public int mtype(){
        return this.ttype;
    }

    public Dir getDir(){
	return stat;
    }
    
}
