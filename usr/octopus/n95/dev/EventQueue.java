/*
 * EventQueue.java
 *
 * Created on 20 de octubre de 2007, 16:16
 */
package dev;

public class EventQueue{
    
    private int size=50;
    private String[] buffer;
    private int endq;

    public EventQueue(){
	buffer=new String[size];
	endq=0;
    }

    public void put(String ev){
	if (endq==size){
	    size=size*2;
	    String[] bufaux=new String[size];
	    for (int i=0;i<endq;i++)
		bufaux[i]=buffer[i];
	    buffer=bufaux;
	}
	buffer[endq++]=ev;
    }

    public String get(){
	if (endq==0)
	    return null;
	
	String s=buffer[0];
	for (int i=0;i<endq-1;i++)
	    buffer[i]=buffer[i+1];
	endq--;

	return s;
    }
}
