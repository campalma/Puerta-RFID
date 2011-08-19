#include <EEPROM.h>
#include <Wire.h>
#include "NewSoftSerial.h"
#include "FAT16.h"
#include "Rfid.h"
#include "utils.h"

// Pins
#define txSoftSerial 3
#define LED 4
#define rxSoftSerial 5
#define RELAY 6
#define CS    8
#define WRITELED 10
#define MOSI    11
#define MISO    12
#define SCK    13

// States
#define READ 1
#define MASTER 2
#define NOTMASTER 3
#define CSHARP 4

// Master state timeout
#define MASTER_TIMEOUT 10000

// C# actions
#define SHOWALL 49
#define EDITCARD 50
#define DELCARD 51
#define EDITMASTER 52
#define SHOWMASTER 53
#define APPMASTER 54
#define PING 55

// Constants
#define LINE 18
#define DS1307_I2C_ADDRESS 0x68

// Objects
NewSoftSerial Softserial(rxSoftSerial,txSoftSerial);
FAT fat;
Rfid rfid;

// RTC variables
byte second;        // 0-59
byte minute;       // 0-59
byte hour;          // 1-23
byte dayOfWeek;     // 1-7
byte dayOfMonth;    // 1-28/29/30/31
byte month;         // 1-12
byte year;
char date[11];
char time[9];

// States variables
int state;
int master;
unsigned long cstime;
unsigned long mtime;

// MicroSD initialized
uint8_t fat_init;

/*
* Arduino setup function
 */
void setup(){
  //Set up the pins for the microSD shield
  pinMode(CS, OUTPUT);
  pinMode(MOSI, OUTPUT);
  pinMode(MISO, INPUT);
  pinMode(SCK, OUTPUT);

  // Set up pins for SoftSerial Communication
  pinMode(rxSoftSerial,INPUT);
  pinMode(txSoftSerial,OUTPUT);

  // Set up pins for Relay and Leds
  pinMode(LED,OUTPUT);
  pinMode(WRITELED, OUTPUT);
  pinMode(RELAY,OUTPUT);

  // Fat initialize
  fat = FAT();
  fat_init = fat.initialize();
  
  // Start Serial Communication
  Softserial.begin(9600);
  Serial.begin(9600);

  // Wire RTC
  Wire.begin();

  // RTC init
  if(ReadDs1307(0x08) != 0xaa)
  {
    second = 0;
    minute = 12;
    hour = 15;
    dayOfWeek = 1;
    dayOfMonth = 1;
    month = 9;
    year = 10;
    SetDateDs1307(second, minute, hour, dayOfWeek, dayOfMonth, month, year);   
    WriteDs1307(0x08,0xaa); 
  }
  state = READ;
  master = 0;

  /* Uncomment to reset EEPROM  
   reset();
   //*/

  /* Uncomment to set Mastercard (eg: 00540275)
  setMaster("00540275");
  //*/

  /* Uncomment to set date and time
   
   second = 0;
   minute = 53;
   hour = 14;
   dayOfWeek = 1;
   dayOfMonth = 8;
   month = 8;
   year = 11;
   SetDateDs1307(second, minute, hour, dayOfWeek, dayOfMonth, month, year); 
   //*/
}

/*
* Arduino loop function
 */
void loop(){
  switch(state){
    case(READ):
    // Device on reading mode
    rfid.Read(Softserial);
    if(rfid.available==1){
      rfid.available = 0;
      if(isMaster(rfid.buffer)==1){
        state = MASTER;
      }
      else{
        state = NOTMASTER;
      }
    }
    break;

    case(MASTER):
    // Set device to save next card
    if(master == 0){
      mtime = millis();
      master = 1;
    }
    digitalWrite(LED,LOW);
    if(MASTER_TIMEOUT < millis()-mtime){
      state = READ;
      master = 0;
      break;
    }
    rfid.Read(Softserial);
    if(rfid.available==1){
      if(isMaster(rfid.buffer)==1){
        // Serial.println("No se puede agregar la tarjeta maestra!");
        Serial.println("MASTER");
      }
      else if(canPass(rfid.buffer)){
        // Serial.println("Esta tarjeta ya se encuentra grabada");
        Serial.println("NO");
      }
      else
        addCard(rfid.buffer);
      state = READ;
      rfid.available = 0;
      master = 0;
      break;
    }
    delay(500);
    digitalWrite(LED,HIGH);
    delay(500);
    break;

    case(NOTMASTER):
    // Checks if card may pass
    if(canPass(rfid.buffer)){
      digitalWrite(RELAY,HIGH);
      digitalWrite(LED,HIGH);
      delay(1000);
      digitalWrite(RELAY,LOW);
      digitalWrite(LED,LOW);
      Write(rfid.buffer,"Aceptado");
      // Serial.println("Puede entrar");
    }
    else{
      for(int i =0; i<3; i++){
        digitalWrite(LED,HIGH);
        delay(150);
        digitalWrite(LED,LOW);
        delay(150);
      }
      Write(rfid.buffer,"Rechazado");
      // Serial.println("No puede entrar");
    }
    rfid.available = 0;
    state = READ;
    break;

    case(CSHARP):
    // C# app communication
    if(Serial.available()){
      char buf[17];
      int small;
      long medium;
      byte modified;
      byte last;
      byte action = Serial.read();
      byte freeline = EEPROM.read(0);

      switch(action){
        case(SHOWALL):
        // Show all cards
        showAll();
        break;

        case(EDITCARD):
        // Edit/Add card
        delay(100);
        modified = Serial.read();
        if(modified == freeline){
          EEPROM.write(0,freeline+1);
        }
        EEPROM.write(LINE*modified,255);
        EEPROM.write(LINE*modified+1,255);
        for(int i = 2; i<18; i++){
          buf[i] = Serial.read();
          EEPROM.write(LINE*modified+i,buf[i]);
        }
        break;

        case(DELCARD):
        // Delete card
        delay(100);
        modified = Serial.read();
        last = freeline-1;
        // Swap last card added with deleted one
        for(int i = 0; i<18; i++){
          byte lastdata = EEPROM.read(LINE*last+i);
          EEPROM.write(LINE*modified+i,lastdata);
          EEPROM.write(LINE*last+i,255);
        }
        EEPROM.write(0,last);
        break;

        case(EDITMASTER):
        // Edit Master card
        delay(100);
        for(int i = 0; i<8; i++){
          buf[i] = Serial.read();
        }
        setMaster(buf);
        break;

        case(SHOWMASTER):
        delay(100);         
        // Returns mastercard
        if(EEPROM.read(1)==255){
          for(int i = 3; i<11; i++){
            buf[i-3] = EEPROM.read(i);
          } 
          buf[8] = '\0';
        }
        else{
          small = 0;
          medium = 0;
          small ^= convert(EEPROM.read(5));
          small = small << 4;
          small ^= convert(EEPROM.read(6));
          itoa(small,buf,10);
          strpad(buf,3);
          Serial.print(buf);
          for(int j = 0; j<4; j++){
            medium = medium << 4;
            medium ^= convert(EEPROM.read(7+j));
          }
          ltoa(medium,buf,10);
          strpad(buf,5);
        }
        Serial.println(buf);
        break;

        case(APPMASTER):
        // Master state from application
        state = MASTER;
        break;

        case(PING):
        // Ping
        Serial.println("PING");
        break; 
      }
    }
    else{
      state = READ;
    }
    break;
  }
  if(Serial.available()){
    state = CSHARP;
  }
}

/*
* Transform full-card into hash-card and save it in destination
*/
void toHash(char *card, char* destination){
  int small = 0;
  long medium = 0;
  small ^= convert(card[4]);
  small = small << 4;
  small ^= convert(card[5]);
  itoa(small,destination,10);
  strpad(destination,3);  
  for(int j = 0; j<4; j++){
    medium = medium << 4;
    medium ^= convert(card[6+j]);
  }
  char *dpointer = &destination[3];
  ltoa(medium,dpointer,10);
  strpad(dpointer,5);
}

/*
* Returns all stored cards on EEPROM
 */
void showAll(){
  char buf[17];
  int small;
  long medium;
  byte action = Serial.read();
  byte freeline = EEPROM.read(0);
  Serial.println(freeline-1);    
  for(int i = 1; i<freeline; i++){
    small = 0;
    medium = 0;
    for(int j = 10; j<18; j++){
      buf[j-10] = EEPROM.read(i*LINE+j);
    }
    buf[8] = '\0';
    Serial.print(buf);

    // Is hash?
    if(EEPROM.read(i*LINE)==255){
      for(int j = 2; j<10; j++){
        buf[j-2] = EEPROM.read(i*LINE+j);
      }
      buf[8] = '\0'; 
      Serial.println(buf);
    }
    // Full card data
    else{
      small ^= convert(EEPROM.read(i*LINE+4));
      small = small << 4;
      small ^= convert(EEPROM.read(i*LINE+5));

      itoa(small,buf,10);
      strpad(buf,3);
      Serial.print(buf);
      for(int j = 0; j<4; j++){
        medium = medium << 4;
        medium ^= convert(EEPROM.read(i*LINE+6+j));
      }
      ltoa(medium,buf,10);
      strpad(buf,5);
      Serial.println(buf);
    }
  }
}

/*
* Adds card on EEPROM
 */
void addCard(char *card){
  int free_line = EEPROM.read(0);
  for(int i = 0; i<10; i++){
    EEPROM.write(free_line*LINE+i,rfid.buffer[i]);
  }
  EEPROM.write(0,free_line+1);
  //  Write(rfid.buffer,"Tarjeta agregada","log.csv");
  Serial.println("OK");
  //  Serial.print("Se agrego la tarjeta: ");
  //  Serial.println(rfid.buffer);
}

/* 
 * Checks if card may pass
 * Also saves card if it's stored as hash
 */
boolean canPass(char *card){
  if(lineNumber(card)>0)
    return true;
  return false;
}

int lineNumber(char *card){
  int free_line = EEPROM.read(0);
  byte value;
  for(int i = 1; i<free_line; i++){
    if(EEPROM.read((free_line-i)*LINE)!=255){
      // Full card data line
      int j = 0;
      while(j<10){
        value = EEPROM.read((free_line-i)*LINE+j);
        if(value != card[j])
          break;
        j++;
      }
      if(j==10){
        return free_line-i;
      }
    }
    else{
      // Hash data line
      char smlstr[4];
      char medstr[6];
      int small = 0;
      long medium = 0;
      boolean pass = true;

      small ^= convert(card[4]);
      small = small << 4;
      small ^= convert(card[5]);
      for(int j = 6; j<10; j++){
        medium = medium << 4;
        medium ^= convert(card[j]);
      }
      itoa(small,smlstr,10);
      ltoa(medium,medstr,10);

      strpad(smlstr,3);
      strpad(medstr,5);

      for(int j = 0; j<3; j++){
        if(EEPROM.read((free_line-i)*LINE+j+2)!=smlstr[j])
          pass = false;
      }
      for(int j = 3; j<8; j++){
        if(EEPROM.read((free_line-i)*LINE+j+2)!=medstr[j-3])
          pass = false;
      }
      if(pass){
        for(int j = 0; j<10; j++){
          EEPROM.write((free_line-i)*LINE+j,card[j]);
        }
        return free_line-i;
      }
    }
  }
  return -1;
}

/*
* Sets mastercard
 */
void setMaster(char *master){
  EEPROM.write(1,255);
  for(int i = 3; i< 11; i++){
    EEPROM.write(i,master[i-3]);
  } 
}

/*
* Checks if card is mastercard
 * Also saves mastercard if it's stored as hash
 */
boolean isMaster(char *card){
  if(EEPROM.read(1)==255){
    //Hash data line
    char smlstr[4];
    char medstr[6];
    int small = 0;
    long medium = 0;

    small ^= convert(card[4]);
    small = small << 4;
    small ^= convert(card[5]);
    for(int j = 6; j<10; j++){
      medium = medium << 4;
      medium ^= convert(card[j]);
    }
    itoa(small,smlstr,10);
    ltoa(medium,medstr,10);

    strpad(smlstr,3);
    strpad(medstr,5);

    for(int j = 0; j<3; j++){
      if(EEPROM.read(j+3)!=smlstr[j])
        return false;
    }
    for(int j = 3; j<8; j++){
      if(EEPROM.read(j+3)!=medstr[j-3])
        return false;
    }
    for(int j = 0; j<10; j++){
      EEPROM.write(j+1,card[j]);
    }
  }
  else{
    //Full data line
    for(int i = 0; i<10; i++){
      if(card[i]!=EEPROM.read(i+1)){
        return false;
      }
    }
  }
  return true;
}

/*
* Resets EEPROM data
 */
void reset(){
  EEPROM.write(0,1);
  for(int i = 1; i<512; i++){
    EEPROM.write(i,255);
  }
}

/*
* Writes a log line on filename
 */
void Write(char *card, char *action){
  int line;
  int value;
  char username[9];
  char filename[15];
  char hash[10];
  
  if(fat_init == 0){
    fat_init = fat.initialize();
  }
  
  if(fat.sd_available()==1){
    delay(250);
    digitalWrite(WRITELED,HIGH);
    
    GetDateDs1307(&second,&minute,&hour,&dayOfWeek,&dayOfMonth,&month,&year);
    Date2Str(date);
    Time2Str(time);
    for(int i = 0; i<10; i++){
      if(date[i+3]=='/'){
        filename[i] = '_';
      }
      else{
        filename[i] = date[i+3];
      }
    }
    filename[7] = '\0';
    strcat(filename,".csv");
    
    fat.create_file(filename);
    fat.open();
    fat.write(date);
    fat.write(";");
    fat.write(time);
    fat.write(";");
    toHash(card,hash);
    fat.write(hash);
    fat.write(";");
    line = lineNumber(card);
    if(line>0){
      value = EEPROM.read(LINE*line+10);
      if(value!=255 && value!=32){
        for(int i = 0; i<8; i++){
          value = EEPROM.read(LINE*line+10+i);
          username[i] = value;
        }
        username[8] = '\0';
        fat.write(username);
      }
    }
    fat.write(";");
    fat.write(action);
    fat.write(";\n");
    fat.close();
    delay(250);
    digitalWrite(WRITELED,LOW);
  }
  else{
    fat_init = 0;
  }
}

/*
* RTC functions
 */

// 1) Sets the date and time on the ds1307
// 2) Starts the clock
// 3) Sets hour mode to 24 hour clock
// Assumes you're passing in valid numbers
void SetDateDs1307(byte second,        // 0-59
byte minute,        // 0-59
byte hour,          // 1-23
byte dayOfWeek,     // 1-7
byte dayOfMonth,    // 1-28/29/30/31
byte month,         // 1-12
byte year)          // 0-99
{
  Wire.beginTransmission(DS1307_I2C_ADDRESS);
  Wire.send(0);
  Wire.send(DecToBcd(second));    // 0 to bit 7 starts the clock
  Wire.send(DecToBcd(minute));
  Wire.send(DecToBcd(hour));      // If you want 12 hour am/pm you need to set
  // bit 6 (also need to change readDateDs1307)
  Wire.send(DecToBcd(dayOfWeek));
  Wire.send(DecToBcd(dayOfMonth));
  Wire.send(DecToBcd(month));
  Wire.send(DecToBcd(year));
  Wire.endTransmission();
}

// Gets the date and time from the ds1307
void GetDateDs1307(byte *second,byte *minute,byte *hour,byte *dayOfWeek,byte *dayOfMonth,byte *month,byte *year)
{
  // Reset the register pointer
  Wire.beginTransmission(DS1307_I2C_ADDRESS);
  Wire.send(0);
  Wire.endTransmission();

  Wire.requestFrom(DS1307_I2C_ADDRESS, 7);

  // A few of these need masks because certain bits are control bits
  *second     = BcdToDec(Wire.receive() & 0x7f);
  *minute     = BcdToDec(Wire.receive());
  *hour       = BcdToDec(Wire.receive() & 0x3f);  // Need to change this if 12 hour am/pm
  *dayOfWeek  = BcdToDec(Wire.receive());
  *dayOfMonth = BcdToDec(Wire.receive());
  *month      = BcdToDec(Wire.receive());
  *year       = BcdToDec(Wire.receive());
}

void WriteDs1307(byte address,byte data)
{
  Wire.beginTransmission(DS1307_I2C_ADDRESS);
  Wire.send(address);
  Wire.send(data);
  Wire.endTransmission(); 
}

byte ReadDs1307(byte address)
{
  Wire.beginTransmission(DS1307_I2C_ADDRESS);
  Wire.send(address);
  Wire.endTransmission();
  Wire.requestFrom(DS1307_I2C_ADDRESS, 1);
  return Wire.receive();
}

void Date2Str(char* buf)
{
  if(dayOfMonth < 10)
    *(buf++) = '0';
  itoa(dayOfMonth,buf,10);
  buf+=strlen(buf);
  *(buf++) = '/';
  if(month < 10)
    *(buf++) = '0';
  itoa(month,buf,10);
  buf+=strlen(buf);
  strcpy(buf,"/20");
  buf+=strlen(buf);
  itoa(year,buf,10);
}

void Time2Str(char* buf)
{
  if(hour < 10)
    *(buf++) = '0';
  itoa(hour,buf,10);
  buf+=strlen(buf);
  *(buf++) = ':';
  if(minute < 10)
    *(buf++) = '0';
  itoa(minute,buf,10);
  buf+=strlen(buf);
  *(buf++) = ':';
  if(second < 10)
    *(buf++) = '0';
  itoa(second,buf,10);  
}
