/*
 * Rreaderror.java
 *
 * Creada on 27 de mayo de 2007, 20:26
 *
 * Autor: Sergio de Mingo (sdemingo AT gmail com)
 * Descripcion:
 */

package op;

public class Rreaderror extends Rmsg implements Enviroment{
    
    String error;
    
    public Rreaderror(int t,String e) {
        super(t,RERROR);
        error=e;
    }
    
    public int packesize(){
        int m1=H;
        m1+= error.getBytes().length; 
        //Nota: en limbo nemo añade STR porque en todos los string se mete
        //      tambien su longitud.
        
        return m1;
    }
    
    public byte[] pack(){
        
        int ps=this.packesize();
        byte []buf=super.packhdr(ps);
        
        int o=H;
        System.arraycopy(error.getBytes(),0,buf,0,error.getBytes().length);
        
        return buf;
    }
    
    public String text(){
        String s="Rreaderror "+this.tag+" ["+this.error+"]";
        return s;
    }
    
    public int mtype(){
        return this.ttype;
    }
    
}
