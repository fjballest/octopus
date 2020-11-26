/*
 * Enviroment.java
 *
 * Creada on 24 de mayo de 2007, 19:47
 *
 * Autor: Sergio de Mingo (sdemingo AT gmail com)
 * Descripcion: Constantes propias de Op
 */

package op;


public interface Enviroment {
    
    public final int BIT8SZ=1;  //final puede dar problemas en J2ME
    public final int BIT16SZ=2;
    public final int BIT32SZ=4;
    public final int BIT64SZ=8;
    public final int QIDSZ=BIT8SZ + BIT32SZ + BIT64SZ;
    
    public final int NOFD=~0;
    
    public final int STATFIXLEN=BIT16SZ+QIDSZ+5*BIT16SZ+4*BIT32SZ+BIT64SZ;
    public final int MAXDATA=16*1024;
    
    public final int MAXHDR=1024;
    
    public final int TATTACH=1;
    public final int RATTACH=2;
    public final int TERROR=3;
    public final int RERROR=4;
    public final int TFLUSH=5;
    public final int RFLUSH=6;
    public final int TPUT=7;
    public final int RPUT=8;
    public final int TGET=9;
    public final int RGET=10;
    public final int TREMOVE=11;
    public final int RREMOVE=12;
    public final int TMAX=13;
    
    public final int ERRMAX=128;
    
    public final int ODATA=1<<1;
    public final int OSTAT=1<<2;
    public final int OCREATE=1<<3;
    public final int OMORE=1<<4;
    public final int OREMOVEC=1<<5;
    
    public final int QTDIR=0x80;
    public final int QTAPPEND=0x40;
    public final int QTEXCL=0x20;
    public final int QTAUTH=0x08;
    public final int QTFILE=0x00;
    
    
    //constantes propias de Ophandler
    public static int H = BIT32SZ + BIT8SZ + BIT16SZ;
    public static int STR = BIT16SZ;
    public static int OFFSET = BIT64SZ;
    public static int COUNT = BIT32SZ;
    public static int TAG = BIT16SZ;
    public static int QID = BIT8SZ +  BIT32SZ + BIT64SZ;
    
    

    public static int LEN = BIT16SZ;

    public static int NULLFD = -2;

    //constantes propias de Sys
    public static int DMDIR = 0x80000000;
    public static int ORCLOSE = 0x40;
    
    
}
