/*
 * Connection.java
 *
 * Creada on 2 de mayo de 2007, 10:20
 *
 * Autor: Sergio de Mingo (sdemingo AT gmail com)
 * Descripcion: Se ha ido modificando y adaptando para hacerla funcionar en J2ME
 */

package ox;

import java.io.*;
//import java.nio.*;  //posibles problemas con J2ME
import javax.microedition.io.*;

public class Connection {
    
    private SocketConnection socket;
    private InputStream input;
    private OutputStream output;
    

    public Connection(SocketConnection s){
	try {
            socket=s;
            input=socket.openInputStream();
            output=socket.openOutputStream();
        } catch (IOException ex) {
            ex.printStackTrace();
        } 
    }


    public void close(){
	try {   
	    socket.close();
	    input=null;
	    output=null;
	} catch (IOException ex) {
            ex.printStackTrace();
	}
    }
    
    /*
     * Lee los bytes indicados. Es bloqueante.
     */
    public int readn(byte []buf, int size)
    {
        try {
            if (buf.length<size)
                throw new IOException("Buffer so little");
            
            int offset=0;
            int total=size;
            int leidos=0;
            int leer=total-leidos;
            int n;
          
            do{
                n=input.read(buf,leidos,leer);
                leidos+=n;
                leer=total-leidos;
            }while ( (leidos<total) && (n>=0));
            
            return leidos;
            
        } catch (IOException ex) {
            ex.printStackTrace();
            return 0;
        }
    }
    
    public void write(byte []buf){

        try {      
            output.write(buf);
	    output.flush(); 
        } catch (IOException ex) {
            ex.printStackTrace();
        }
    }
    
}
