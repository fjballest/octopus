/*
 * Rput.java
 *
 * Creada on 23 de Junio de 2007, 20:26
 *
 * Autor: Sergio de Mingo (sdemingo AT gmail com)
 * Descripcion:
 */

package op;

public class Rput extends Rmsg implements Enviroment{
    
    private int fd;
    private int count;
    private Qid qid;
    private int mtime;
    
    public Rput(int t,int f,int c,Qid q, int m) {
        super(t,RPUT);
	fd=f;
	count=c;
	qid=q;
	mtime=m;
	
    }
    
    public int packesize(){

        int m1=H;
        m1 += BIT16SZ;
	m1 += COUNT;
	m1 += QIDSZ;
	m1 += BIT32SZ;
        
        return m1;
    }
    
    public byte[] pack(){
        
	int ps=this.packesize();
        byte []buf=super.packhdr(ps);
       
	int o=H;
	buf=Ophandler.p16(buf,o,this.fd);
	o+=BIT16SZ;
	buf=Ophandler.p32(buf,o,this.count);
	o+=BIT32SZ;
	buf=this.qid.pack(buf,o);
	o+=QIDSZ;
	buf=Ophandler.p32(buf,o,this.mtime);
	
        return buf;
    }
    
    public String text(){
        //String s="Rget "+this.tag +" ["+this.path+"] fd="+this.fd+" mode="+Ophandler.mode2text(this.mode);
	String s= "Rput "+this.tag+" fd="+this.fd+" "+this.count+" "+this.qid.toString()+" "+this.mtime;
        return s;
    }
    
    public int mtype(){
        return this.ttype;
    }
    
}
