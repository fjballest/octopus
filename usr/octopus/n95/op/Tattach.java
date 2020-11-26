/*
 * Tattach.java
 *
 * Creada on 27 de mayo de 2007, 20:57
 *
 * Autor: Sergio de Mingo (sdemingo AT gmail com)
 * Descripcion:
 */

package op;

public class Tattach extends Tmsg implements Enviroment{
    
    private String uname;
    private String path;
    
    public Tattach(int t,String u,String p) {
        super(t,TATTACH);
        uname=u;
        path=p;
    }

    public int packesize(){
        int m1=H;
	m1+= STR + uname.length();
	m1+= STR + path.length();
        return m1;
    }
    
    public byte[] pack(){
	int ps=this.packesize();

        byte []buf=super.packhdr(ps);
	int off=H;
	buf=Ophandler.pstring(buf,off,this.uname);
	off+=this.uname.getBytes().length + STR;
	
	buf=Ophandler.pstring(buf,off,this.path);
        
        return buf;
    }
    
    public String text(){
        String s="Tattach "+this.tag+" ["+this.uname+"]["+this.path+"]";
        return s;
    }
    
    public int mtype(){
        return this.ttype;  //TREMOVE
    }
}
