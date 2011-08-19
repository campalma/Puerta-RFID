#include "utils.h"
#include <string.h>

/*
* Leftpads str with zeros 
*/
void strpad(char *str,int length){
  char aux[length+1];
  for(int i = 0; i<length; i++){
    aux[i] = '0';
  }
  aux[length] = '\0';
  for(int i = 0; i<strlen(str); i++){
    aux[length-1-i] = str[strlen(str)-1-i];
  }
  for(int i = 0; i<length+1; i++){
    str[i] = aux[i];
  }
}

/*
* Converts HEX char to number
*/
byte convert(byte a){
  if(a<58)
    return a-48;
  else
    return a-55;
}

byte DecToBcd(byte val)
{
  return ( (val/10*16) + (val%10) );
}
 
// Convert binary coded decimal to normal decimal numbers
byte BcdToDec(byte val)
{
  return ( (val/16*10) + (val%16) );
}
