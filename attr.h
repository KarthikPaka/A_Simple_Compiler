/**********************************************
        CS515  Project 2
        Fall  2018
        Student Version
**********************************************/

#ifndef ATTR_H
#define ATTR_H

typedef union {int num; char *str;} tokentype;

typedef struct {
        int targetRegister;
} regInfo;

typedef struct linkedListNode {
	char identifierName[50];
	struct linkedListNode *next;
} linkedListNode;

typedef struct labelInfo {
        int labelOne;
        int labelTwo;
        int labelThree;
        int targetRegister;
} labelInfo;

typedef struct typeSpecs {
	int isArray;
	int size;
} typeSpecs;

typedef struct ctrlExp {
	int num;
	int upperBoundReg;
} ctrlExp;

#endif


  
