/*
 * Tremove.java
 *
 * Creada on 26 de mayo de 2007, 16:06
 *
 * Autor: Sergio de Mingo (sdemingo AT gmail com)
 * Descripcion:
 */

package op;

public class Tremove extends Tmsg implements Enviroment{
    
    private String path;
    
    public Tremove(int t,String p) {
        super(t,TREMOVE);
        path=p;
    }

    public int packesize(){
        int m1=H;
	m1+= STR + path.length();
        return m1;
    }
    
    public byte[] pack(){
	
	int ps=this.packesize();

        byte []buf=super.packhdr(ps);
	buf=Ophandler.pstring(buf,H,this.path);
        
        return buf;
    }
    
    public String getPath(){
	return path;
    }
    public String text(){
        String s="Tremove "+this.tag+" ["+path+"]";
        return s;
    }
    
    public int mtype(){
        return this.ttype;  //TREMOVE
    }
    
}
