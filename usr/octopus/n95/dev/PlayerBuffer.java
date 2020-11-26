/*
 * OServer.java
 *
 * Creado en 2 de Agosto de 2007, 10:14
 * Descripcion: Es una extension de un InputStream de Bytes. Su funcion es permitir añadir
 *              manualmente arrays de bytes a un InputStream para que se vayan reproduciendo.
 */

package dev;

import java.io.*;
import java.util.*;

public class PlayerBuffer extends ByteArrayInputStream{

    public PlayerBuffer(byte[] buf){
	super(buf);
    }

    public void append(byte[] ap){

	byte[] newbuf=new byte[count+ap.length];
	System.arraycopy(buf,0,newbuf,0,count);
	System.arraycopy(ap,0,newbuf,count,ap.length);

	/*
	 * buf and count are in the superclass 
	 */
	buf=newbuf;
	count=count+ap.length;
    }

    public void reset(){
	pos=0;
    }

    public int rest(){
	return count-pos;
    }

    public String toString(){
	String s="pos: "+pos+" count: "+count+" mark: "+mark;
	return s;
    }
}
