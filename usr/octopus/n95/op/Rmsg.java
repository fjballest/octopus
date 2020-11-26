/*
 * Rmsg.java
 *
 * Creada on 27 de mayo de 2007, 20:20
 *
 * Autor: Sergio de Mingo (sdemingo AT gmail com)
 * Descripcion:
 */

package op;

import ox.*;

public abstract class Rmsg {
    
    protected int ttype;
    protected int tag;
    
    public Rmsg(int t,int tt) {
        super();
        tag=t;
        ttype=tt;
    }
    
    public abstract int mtype();
    
    public abstract byte[]pack();
    
    public abstract String text();
    
    public int getTag(){
        return tag;
    }
    
    
    protected byte[] packhdr(int ps){
        
        if (ps<=0)
            return null;
        
        byte[] d=new byte[ps];
        d[0] = (byte) ps;
        d[1] = (byte) (ps>>8);
        d[2] = (byte) (ps>>16);
        d[3] = (byte) (ps>>24);
        d[4] = (byte) this.mtype();
        d[5] = (byte) this.tag;
        d[6] = (byte) (this.tag>>8);
        return d;
    }
    
   
    public static Rmsg read (Connection fd, int msize)
    {
        byte[]buf=null;
        
        buf=Ophandler.readmsg(fd,msize);
        
        if (buf == null)
            return null;
            
        Rmsg msg=Ophandler.unpackRmsg(buf);
        if (msg==null)
            System.out.println ("no se ha desempaquetado");
        return msg;
    }
    
    
    
    
}
