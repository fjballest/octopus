/*
 * Rerror.java
 *
 * Creada on 27 de mayo de 2007, 20:26
 *
 * Autor: Sergio de Mingo (sdemingo AT gmail com)
 * Descripcion:
 */

package op;

public class Rerror extends Rmsg implements Enviroment{
    
    String ename;
    
    public Rerror(int t,String e) {
        super(t,RERROR);
        ename=e;
    }
    
    public int packesize(){
        int m1=H;
        m1+= STR + ename.getBytes().length; 
        
        return m1;
    }
    
    public byte[] pack(){
        
        int ps=this.packesize();
        byte []buf=super.packhdr(ps);
        
        int off=H;
	buf=Ophandler.pstring(buf,off,this.ename);
	off+=STR+this.ename.getBytes().length;

        return buf;
    }
    
    public String text(){
        String s="Rerror "+this.tag+" ["+this.ename+"]";
        return s;
    }
    
    public int mtype(){
        return this.ttype;
    }
    
}
