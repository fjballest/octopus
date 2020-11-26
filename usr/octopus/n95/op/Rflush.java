/*
 * Rerror.java
 *
 * Creada on 27 de mayo de 2007, 20:26
 *
 * Autor: Sergio de Mingo (sdemingo AT gmail com)
 * Descripcion:
 */

package op;

public class Rflush extends Rmsg implements Enviroment{
    
    public Rflush(int t) {
        super(t,RFLUSH);
    }
    
    public int packesize(){
        int m1=H;
        return m1;
    }
    
    public byte[] pack(){
        
        int ps=this.packesize();
        byte []buf=super.packhdr(ps);
        
        return buf;
    }
    
    public String text(){
        String s="Rflush "+this.tag;
        return s;
    }
    
    public int mtype(){
        return this.ttype;
    }
    
}
