/*
 * Dev.java
 *
 * Creada on 4 de septiembre de 2007, 19:47
 *
 * Autor: Sergio de Mingo (sdemingo AT gmail com)
 * Descripcion: Esqueleto de cualquier device del telefono
 */


package dev;

import op.*;


public interface Dev{

    public void disable();

    public int open(String path,int mode);
    
    public int create(String path,int mode);

    public boolean remove(String path);

    public Dir stat(String path);

    public Dir stat(int fd);

    public  int read(int fd, byte[]data,int count, long off);

    public int write(int fd,byte[]buf, int count, long off);

    //private int path2id(String path);
}
