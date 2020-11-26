/*
 * ContactSystem.java
 *
 * Creado en 25 de septiembre de 2007, 10:14
 * Descripcion: 
 */


package dev;

import javax.microedition.pim.*;
import java.util.*;
import java.io.*;
import op.*;
import ox.*;


public class ContactSystem implements Dev,Enviroment{
  
    public static final int CONTACTDEVS=1;
    public static final int CONTID=0;

    public static final int MAX_CONTACTS=600;

    private OSystem osystem;
    private String rootpath;
    private Dir[] files;
    private ContactList list;
    private Contact[] cache;
    private int szcache;


    private boolean loaded;
    private boolean readed;

    public ContactSystem(OSystem os){	

	osystem=os;
	
	rootpath="/contacts";
        files=new Dir[CONTACTDEVS];

	Qid contqid=new Qid(QTFILE);
        Dir contdir=new Dir("contacts",Dir.USER,Dir.USER,Dir.USER,contqid);
	files[CONTID]=contdir;
	osystem.regdev(this,contdir,OSystem.CONTACTDEV);

	readed=false;
	loaded=false;
    }

    public void disable(){

    }

    
    public int open(String path,int mode){
        
	if (path.equals(rootpath))
	    return CONTID;
	else
            return NULLFD;
    }

    public int create(String path,int mode){
	
        return NULLFD; //no se puede crear
    }


    public boolean remove(String path){

	return false; //no se puede borrar
    }
    
   

    public Dir stat(String path){
    
	if (path.equals(rootpath))
	    return files[CONTID];
        else
            return null;
    }


    public Dir stat(int fd){

	String p=osystem.fd2path(fd);
	return stat(p);
    }
    

    public  int read(int fd, byte[]data,int count, long off){
	
	String p=osystem.fd2path(fd);
	int id=path2id(p);

	switch(id){
	case CONTID:
	    if (!loaded)
		loadContactList();
	    
	    if (readed==true){   //CHAPUZA??
		readed=false;
		return 0;
	    }else{
		byte[] bc=readContactList();
		System.arraycopy(bc,0,data,0,bc.length);
		readed=true;
		if (data!=null)
		    return bc.length;
		else
		    return -1;
	    }
	    
	default:
	    return -1;
	}
    }


    public int write(int fd,byte[]buf, int count, long off){

	String p=osystem.fd2path(fd);
	int id=path2id(p);

	/*
	  Cuidado: si ejecuto esto cada vez que cambie algo me va a meter todos los contactos
	  otra vez en la lista.
	  Debo ir comprobando si ya existen o no.

	

	try{
	    InputStream in=new ByteArrayInputStream(buf);
	    PIMItem[] incontacts=PIM.getInstance().fromSerialFormat(in,null); //null is UTF-8 for default
	    for (int i=0;i<incontacts.length;i++){
		Contact incont=(Contact)incontacts[i];

		try{
		    if (!existsInCache(incont)){
			//el contacto no existe en la cache.
			cache[szcache++]=incont; //lo inserto
		    }
		    
		}catch(Exception e){
		    OxportMIDlet.addtext("ERROR: One contact bad formatted");
		}
	    }
	    writeContactList();
	    
	    //una vez sobre escrita toda la lista solo queda recargarla
		
	}catch(Exception e){
	    OxportMIDlet.addtext("ERROR: Contact List cannot writed");
	    return -1;
	}
	*/
	return -1;
    }




    private int path2id(String path){
	if (path.equals(rootpath))
	    return CONTID;
	else 
            return NULLFD;
    }




    /*
     * Carga la lista de contactos en cache para que el movil nos pida
     * permiso de lectura solo una vez.
    */
    private void loadContactList(){
	
	cache=new Contact[MAX_CONTACTS];
	szcache=0;

	try {
	    list=(ContactList)PIM.getInstance().openPIMList(PIM.CONTACT_LIST, PIM.READ_ONLY);
	    String[] contacts;
	    Enumeration elementos=list.items();
	    
	    while(elementos.hasMoreElements()){
		cache[szcache]=(Contact)elementos.nextElement();
		szcache++;
	    }
	    loaded=true;
	    
	}catch (PIMException e) {
	    OxportMIDlet.addtext("ERROR: Contact List cannot loaded");
	}
    }



    /*
     * Escribe en la lista de contactos el contenido de la cache
     */
    private void writeContactList(){
	
	for (int i=0;i<szcache;i++){
	    try{
		Contact newc=list.createContact();
		String[] fields=getAllFields(cache[i]);
		String[] name = new String[list.stringArraySize(Contact.NAME)];
		if (list.isSupportedArrayElement(Contact.NAME, Contact.NAME_FAMILY))
		    name[Contact.NAME_FAMILY] = fields[0];
		if (list.isSupportedArrayElement(Contact.NAME, Contact.NAME_GIVEN))
		    name[Contact.NAME_GIVEN] = fields[1];
		newc.addStringArray(Contact.NAME, PIMItem.ATTR_NONE, name);
		if (list.isSupportedField(Contact.TEL))
		    newc.addString(Contact.TEL, 0, fields[2]);
	    
		newc.commit();
		}catch(Exception e){
		    OxportMIDlet.addtext("ERROR: Cannot write one contact");
		}
	    }	
	}


    /*
     * Lee los contactos (a partir de la cache)y los transforma en lineas formateadas
     * que se devuelven al lector.
     */
    private byte[] readContactList(){
	
	try{
	    byte[] data=new byte[MAX_CONTACTS*100];//BUG: 100 bytes for each contact
	    int offset=0;

	    for (int i=0; i<szcache; i++){		
		String line=getFormattedContact(cache[i]);
		byte []strbyte=line.getBytes();
		System.arraycopy(strbyte,0,data,offset,strbyte.length);
		offset+=strbyte.length;
	    }
	    byte[] d=new byte[offset];
	    System.arraycopy(data,0,d,0,offset);
	    return d;
	    
	}catch (Exception pe){
	    System.out.println (pe.toString());
	    OxportMIDlet.addtext("ERROR: Contact List cannot readed");
	    return null;
	}
    }

    
    /*
     * Establece el formato de cada linea del fichero de contactos
     */
    private String getFormattedContact(Contact c){

	String firstname,surname;
	String tel;
	//String[] name = new String[list.stringArraySize(Contact.NAME)];
	
	try{
	    /*
	    if (list.isSupportedField(Contact.NAME)){
		name=c.getStringArray(Contact.NAME,0);
	    	    
		if (list.isSupportedArrayElement(Contact.NAME, Contact.NAME_FAMILY))
		    surname=name[Contact.NAME_FAMILY];
		else
		    surname="-";

		if (list.isSupportedArrayElement(Contact.NAME, Contact.NAME_GIVEN))
		    firstname=name[Contact.NAME_GIVEN];
		else
		    firstname="-";
	    }else{
		firstname="-";
		surname="-";
	    }
		
	    if (list.isSupportedField(Contact.TEL))
		tel=c.getString(Contact.TEL,0);
	    else
		tel="-";
	    */

	    String []fields=getAllFields(c);
	    
	    return fields[0]+":"+fields[1]+":"+fields[2]+"\n";

	}catch(Exception e){
	    return "Contact bad formatted";
	}
    }


    private String[] getAllFields(Contact c) throws Exception{

	String[] n=new String[3]; //BUG: a magic number

	
	String[] name = new String[list.stringArraySize(Contact.NAME)];
	if (list.isSupportedField(Contact.NAME)){
	    name=c.getStringArray(Contact.NAME,0);
	    	    
	    if (list.isSupportedArrayElement(Contact.NAME, Contact.NAME_FAMILY))
		n[0]=name[Contact.NAME_FAMILY];
	    else
		n[0]="-";

	    if (list.isSupportedArrayElement(Contact.NAME, Contact.NAME_GIVEN))
		n[1]=name[Contact.NAME_GIVEN];
	    else
		n[1]="-";
	}else{
	    n[1]="-"; //firstname
	    n[0]="-"; //surname
	}
		
	if (list.isSupportedField(Contact.TEL))
	    n[2]=c.getString(Contact.TEL,0);
	else
	    n[2]="-";

	return n;
    }


    /*
      Indica si el contacto C está en cache. Si algun campo es distinto retorna false.
    */
    private boolean existsInCache(Contact c){
	
	for (int i=0;i<szcache;i++){
	    try{
		String[] fcache=getAllFields(cache[i]);
		String[] fwrite=getAllFields(c);
		if ((!fcache[0].equals(fwrite[0])) || (!fcache[0].equals(fwrite[0])) || (!fcache[0].equals(fwrite[0])))
		    return false;
	    }catch(Exception e){
		return false;
	    }
	}
	return true;
    }
	
}
