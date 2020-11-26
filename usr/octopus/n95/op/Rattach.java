/*
 * Rattach.java
 *
 * Creada on 28 de mayo de 2007, 17:48
 *
 * Autor: Sergio de Mingo (sdemingo AT gmail com)
 * Descripcion:
 */

package op;

public class Rattach extends Rmsg implements Enviroment{
    
    public Rattach(int t) {
        super(t,RATTACH);
    }
    
    public int packesize(){
        int m1=H;
        
        //Nota: en limbo nemo añade STR porque en todos los string se mete
        //      tambien su longitud.
        
        return m1;
    }
    
    public byte[] pack(){
        
        int ps=this.packesize();
        byte []buf=super.packhdr(ps);
        
        return buf;
    }
    
    public String text(){
        String s="Rattach "+this.tag;
        return s;
    }
    
    public int mtype(){
        return this.ttype; 
    }
    
}
