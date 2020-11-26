/*
 * Tremove.java
 *
 * Creada on 26 de mayo de 2007, 16:06
 *
 * Autor: Sergio de Mingo (sdemingo AT gmail com)
 * Descripcion:
 */

package op;

public class Tflush extends Tmsg implements Enviroment{
    
    private int oldtag;
    
    public Tflush(int t,int olt) {
        super(t,TFLUSH);
        oldtag=olt;
    }

    public int packesize(){
        int m1=H;
	m1+= TAG;
        return m1;
    }
    
    public byte[] pack(){
	
	int ps=this.packesize();

        byte []buf=super.packhdr(ps);
	
	int v=this.oldtag;
	buf[H] = (byte) v;
	buf[H+1] = (byte) (v>>8);
        
        return buf;
    }
    
    public String text(){
        String s="Tflush "+this.tag+" ["+this.oldtag+"]";
        return s;
    }
    
    public int mtype(){
        return this.ttype;  
    }
    
}
