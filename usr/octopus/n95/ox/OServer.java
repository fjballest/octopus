/*
 * OServer.java
 *
 * Creado en 2 de Agosto de 2007, 10:14
 * Descripcion: Servidor generico de sistemas virtuales. Este servidor es valido para 
 *              cualquier sistema virtual de dispositivo.
 */


package ox;

import op.*;
import dev.*;
import java.io.*;
import java.util.*;

public class OServer extends Thread implements Enviroment{

    private String expath;
    private Connection con;
    private OSystem osystem;
    private boolean attached;


    public OServer(Connection c){

	expath="";
	attached=false;
	con=c;
	
        osystem=new OSystem();
	
	/* 
	 * Lista de subsistemas que estamos usando. Durante
	 * su creación ellos mismos se registran en OSystem.
	 */
        AudioSystem audiosys     =new AudioSystem(osystem);
	ContactSystem contactsys =new ContactSystem(osystem);
	FileSystem filesys       =new FileSystem(osystem);
	KbdSystem kdbsys         =new KbdSystem(osystem);
	MsgSystem msgsys         =new MsgSystem(osystem);
    }

    
    public void run(){
	
	Tmsg msg=Tmsg.read(con,0);
	int tag=0 ;
	byte []buf=null;
	
	if (msg!=null){
                
	    switch(msg.mtype()) {
	    case Enviroment.TATTACH:
		Tattach tmsg2=(Tattach)msg;
		System.out.println("=> "+tmsg2.text());
		tag=tmsg2.getTag();
		
		Rattach ra=new Rattach(tag);
		buf=ra.pack();
		System.out.println("<= "+ra.text());

		attached=true;
		break;

	    default:
		Rerror e=new Rerror(msg.getTag(),"not attached");
		buf=e.pack(); 
		break;
	    }
	    con.write(buf);
	}
	serve();
    }


    public void abort(){
	
	osystem.abort();
	attached=false;
    }
    
    
    public void serve(){

	while (attached){
	    Tmsg msg=Tmsg.read(con,0);
	    int tag=0 ;
	    byte[] buf=null;
            
	    if (msg!=null){
                
		switch(msg.mtype()) {
		    
		case Enviroment.TATTACH:
		    /* The attached has been made in Oxport class */
		    Rerror er=new Rerror(msg.getTag(),"already attached");
		    buf=er.pack();
		    break;
		    
		  
		case Enviroment.TREMOVE:
		    Tremove tmsg1=(Tremove)msg;
                    System.out.println("=> "+tmsg1.text());
                    Rerror err=new Rerror(tag,"Error in remove");
                    System.out.println("<= "+err.text());
                    buf=err.pack();
                    break;
                        
		case Enviroment.TFLUSH:
		    Tflush tmsg3=(Tflush)msg;
		    System.out.println ("=> "+tmsg3.text());
		    tag=tmsg3.getTag();
                        
		    Rflush rf=new Rflush(tag);
		    buf=rf.pack();
                        
		    break;
                        
		case Enviroment.TGET:
		    Tget tg=(Tget)msg;
		    System.out.println ("=> "+tg.text());
		    tag=tg.getTag();
                        
		    Rmsg r=serveget(tg);
		    if (r.mtype()==RGET){
			Rget rg=(Rget)r;
			buf=rg.pack();
			System.out.println("<= "+rg.text());
		    }else if(r.mtype()==RERROR){
			Rerror re=(Rerror)r;
			buf=re.pack();
			System.out.println("<= "+re.text());
		    }else{
			System.out.println ("serveget no devuelve mas tipos");
		    }
		    
		    break;

		case Enviroment.TPUT:
		    Tput tp=(Tput)msg;
		    System.out.println ("=> "+tp.text());
		    tag=tp.getTag();
		   
		    Rmsg rr=serveput(tp);
		    if (rr.mtype()==RPUT){
			Rput rp=(Rput)rr;
			buf=rp.pack();
			System.out.println("<= "+rp.text());
		    }else if(rr.mtype()==RERROR){
			Rerror re=(Rerror)rr;
			buf=re.pack();
			System.out.println("<= "+re.text());
		    }else{
			System.out.println ("serveput no devuelve mas tipos");
		    }
		    
		    break;
			
		default:
		    Rerror e=new Rerror(0,"Type "+msg.mtype()+ " unknow");
		    buf=e.pack();
                        
		    break;
		} 
		con.write(buf);
                
	    }else{
		tag=0;
	    }
	}
	
    }

    public Rmsg serveput(Tput msg){
	
	int fd=NULLFD;
	int mode=Integer.parseInt("664",8); 
	int mmode= msg.getMode() & (OSTAT | ODATA | OCREATE | OMORE | OREMOVEC);
	int repfd=NOFD;
	boolean isdir=false;
	String mpath=msg.getPath();
	String path=expath+mpath;
	
	int mfd=msg.getFd();

	Dir mstat=msg.getStat();

	if ( (  (  ((mmode&OSTAT)!=0)  &&  ((mstat.mode&DMDIR)!=0)   ) !=false) && (mstat.mode !=  ~0))
	    isdir=true;

//	//1. Prepare FD

	if (mfd!=NOFD){
	    fd=mfd;
	    if ((mmode&OREMOVEC)!=0)
		return new Rerror(msg.getTag(),"put: remove on close note in first put");
	    
	    if ((mmode&OCREATE)!=0){
		fd=NULLFD;
		mfd=NOFD;
	    }else if (fd == NULLFD)
		mfd=NOFD;
	    else if ((mmode&OMORE)!=0)
		repfd=mfd;
	}
	
	if (mfd==NOFD){
	    if ( (mpath == null) || (mpath == "") || ( mpath.charAt(0) !='/'))
		return new Rerror(msg.getTag(), "put: bad Op file name");
	    
	    int omode=0;
	    if ((mmode&OREMOVEC)!=0){
		if ((mmode&OMORE)==0)
		    return new Rerror(msg.getTag(),"put: remove on close on single put: pointless");
		omode|=ORCLOSE;
	    }
	    
	    if ((mmode&OCREATE)!=0){
		if (((mmode&OSTAT)!=0) && isdir){
		    mode |= DMDIR;
		    fd = osystem.create(path,mode);
		}else{
		    fd = osystem.open(path,0);
		    if (fd == NULLFD)
			fd = osystem.create(path,0);
		}
	    }else if (isdir)
		fd = osystem.open (path,0); //fd = open (path, OREAD|omode);
	    else
		fd = osystem.open (path,0); //fd = open (path, OWRITE|omode);

	    if (fd == NULLFD)
		return new Rerror(msg.getTag(),"put: fd"+fd);
	    
	    if ( ((mmode&OMORE)!=0) && !isdir)
		repfd=fd;
	}
	    
	//2. Data and stat I/O. 
	
	mmode &= (OSTAT|ODATA);
	int cnt=0;
	if (  ((mmode&ODATA)!=0) && !isdir){
	    cnt = osystem.write(fd,msg.getData(),msg.getData().length,msg.getOffset());
	    if (cnt <0){
		return new Rerror(msg.getTag(),"write: error");
	    }
	}

	Dir d=osystem.stat(fd); //no actualizamos el stat del device
	fd = NULLFD;
	
	return new Rput(msg.getTag(),repfd,cnt,d.qid,d.mtime);
    }

    public Rmsg serveget(Tget msg){
       
	String path=expath;

	int fd = NULLFD;
	int mfd=msg.getFd();
	String mpath=msg.getPath();
	int mmode = ( msg.getMode() & (OSTAT | ODATA| OMORE )) ;
	int repfd = NOFD;
        
	path=path.concat(msg.getPath());

	if (mfd != NOFD)  //Existe el fd    
	    fd=mfd;
	
	if (mfd == NOFD){  //No existe el fd
	    if ( (mpath == null) || (mpath == "") || ( mpath.charAt(0) !='/'))
		return new Rerror(msg.getTag(), "bad Op file name");

	    fd=osystem.open(path,0);

	    if (fd==NULLFD){
		path=path.substring(path.indexOf(expath),path.length());
		return new Rerror(msg.getTag(), "'"+path+"' does not exist");
	    }
		
	    if ((mmode & OMORE) !=0)
		repfd=fd; 
	}
	    
	mmode &= (ODATA|OSTAT);
	
	Dir stat=null;
	if (fd == NULLFD)
	    stat=osystem.stat(path);
	else
	    stat=osystem.stat(fd);
	
	if (stat==null) {
	    path=path.substring(path.indexOf(expath),path.length());
	    return new Rerror(msg.getTag(), "'"+path+"' does not exist");
	}

        if (stat.name.equals(expath))
            stat.name="/";
        
	Rget rmsg=null;
	
	byte[] vacio=new byte[0];
	if (mmode == OSTAT){   
	    rmsg=new Rget(msg.getTag(),repfd,OSTAT,stat,vacio);
	    return rmsg;
	}
	
	byte[] dat=null;
	byte[] buf=null;
        
        if ((stat.qid.qtype&QTDIR) != 0){
	    repfd = NOFD;

            byte[] dataux=new byte[1024];
	    int l=osystem.read(fd,dataux,0,0);
            dat=new byte[l];
            System.arraycopy(dataux,0,dat,0,l);

	    int sent=0;
	    int rest=dat.length;
	    int mode;
	    int nr;
	    do{
		nr=msg.getCount();
		mode=mmode;
		if (nr > rest)
		    nr =rest;
		else
		    mode |= OMORE;
		mmode &= ~OSTAT;
		buf=new byte[nr];
		System.arraycopy (dat,sent,buf,0,nr);
		rmsg = new Rget(msg.getTag(),repfd,mode,stat,buf);
		sent+=nr;
		rest-=nr;
	    }while((mode&OMORE)!=0);

	}else{
	    int mode;
	    long moffset=msg.getOffset();
	    int nmsgs=msg.getNmsg();
	    
	    do{
		buf=new byte[msg.getCount()];
		
		int nr=osystem.read(fd,buf,msg.getCount(),msg.getOffset());

		if (nr<0)
		    return new Rerror(msg.getTag(), "Error in read");
	    
		if (nr == 0 ){
		    dat=new byte[nr];
		    System.arraycopy(buf,0,dat,0,nr);
		    rmsg = new Rget(msg.getTag(),NOFD,mmode,stat,dat);
		    return rmsg;
		}
		
		moffset+= (long)nr;
		mode=mmode;
		if (moffset < osystem.stat(fd).length && nr >0)
		    mode |= OMORE;
		
		mmode &= ~OSTAT;
		
		dat=new byte[nr];
		System.arraycopy(buf,0,dat,0,nr);
		rmsg = new Rget(msg.getTag(),repfd,mode,stat,dat);

	    }while ( ( --nmsgs!=0 ) && ((mode&OMORE)!=0));
	}	
	return rmsg;
    }
   
}
