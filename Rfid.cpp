#include "Rfid.h"
#include "WProgram.h"
#include "NewSoftSerial.h"

Rfid::Rfid()
{
  available = 0;
  master = "2E0005E6A3";
}

/*
int Rfid::Check()
{
  if(buffer[14]!=3 || buffer[13]!=10 || buffer[12]!=13)
  {
    return -1;
  }
  else
  {
    buffer[12]='\0';
    
    int checksum = 0;
    int aux1, aux2;
    for (int j=0; j<12; j=j+2){
      aux1 = buffer[j]>57? 55:48;
      aux2 = buffer[j+1]>57? 55:48;
      int res = (buffer[j]-aux1)*16+(buffer[j+1]-aux2);
      checksum ^= res;
    }
    if(checksum == 0)
      return 1;
    else
      return -1;
  }
}
*/

int Rfid::Check()
{
/*  if(buffer[10]!=13 || buffer[11]!=10 || buffer[12]!=3){
    return false
  }*/
  buffer[10] = '\0';
  return 1;
}

void Rfid::Print()
{
  if(available){
    for(int i = 0; i<10; i++)
      Serial.print(buffer[i],HEX);
    Serial.print("\n");
  }
}

void Rfid::Read(NewSoftSerial &Softserial)
{
  if(Softserial.available()){
    buffer[0] = Softserial.read();
    delay(50);
    if(buffer[0] == 2 || buffer[0] == 1){
      int i = 0;
      while(i<10){
        if(Softserial.available()){
          buffer[i] = Softserial.read();
          i++;
        }
      }
      available = 1;
      buffer[10] = '\0';
      Softserial.flush();
//      Check();
//      Print();
    }
  }
}
