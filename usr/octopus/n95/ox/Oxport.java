/*
 * Oxport.java
 *
 * Creado en 2 de Agosto de 2007, 10:14
 * Description: Clase principal de Oxport. Esta clase ira levantando cada servicio de 
 *              dispositivo en diferentes puertos.
 */

package ox;

import op.*;
import java.io.*;
import java.util.*;
import javax.microedition.io.*;

public class Oxport  extends Thread implements Enviroment{
    
    public static final int PORT = 7000;

    private OServer server;
    private Connection con;
    private boolean on;
    
    
    public Oxport(){
	on=true;
	server=null;
	con=null;
    }
    

    public void startOxport(){
	
	try{
            ServerSocketConnection ssock=null;
            ssock=(ServerSocketConnection)Connector.open("socket://:"+PORT);
            while (on) {
                SocketConnection sc=(SocketConnection)ssock.acceptAndOpen();
                con=new Connection(sc);
                server=new OServer(con);
                server.start();
            }
        }catch(Exception e){
            e.printStackTrace();
        }
    }

    public void exitOxport(){
	on=false;
	if (con!=null)
	    con.close();
	if (server!=null)
	    server.abort();
    }

    public OServer getOServer(){
	return server;
    }

    
    public void run(){     

        OxportMIDlet.addtext("Conexion abierta ...");
	startOxport();
    }
}
