#ifndef Rfid_h
#define Rfid_h

#include "NewSoftSerial.h"

class Rfid{
  public:
    // Constructor
    Rfid();
    
    // Functions
    void Read(NewSoftSerial &Softserial);
    void Print();
    
    // Variables
    char buffer[15];
    int available;
    
  private:
    // Functions
    int Check();
    
    // Variables
    char *master;
    
};
#endif
