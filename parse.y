%{
#include <stdio.h>
#include "attr.h"
#include "instrutil.h"
int yylex();
void yyerror(char * s);
#include "symtab.h"

//i added this
linkedListNode * insertAtEnd(linkedListNode * head, linkedListNode * lln);

FILE *outfile;
char *CommentBuffer;
 
%}

%union {tokentype token;
        regInfo targetReg;
	linkedListNode *identifierList;
	typeSpecs typeSpec;
       }

%token PROG PERIOD VAR 
%token INT BOOL PRINT THEN IF DO  
%token ARRAY OF 
%token BEG END ASG  
%token EQ NEQ LT LEQ 
%token ELSE
%token FOR 
%token <token> ID ICONST 

%type <typeSpec> type
%type <targetReg> exp 
%type <targetReg> lhs 

// things i added
%type <identifierList> idlist
%type <targetReg> condexp

%start program

%nonassoc EQ NEQ LT LEQ 
%left '+' '-' 
%left '*' 

%nonassoc THEN
%nonassoc ELSE

%%
program : {emitComment("Assign STATIC_AREA_ADDRESS to register \"r0\"");
           emit(NOLABEL, LOADI, STATIC_AREA_ADDRESS, 0, EMPTY);} 
           PROG ID ';' block PERIOD { }
	;

block	: variables cmpdstmt { }
	;

variables: /* empty */
	| VAR vardcls { }
	;

vardcls	: vardcls vardcl ';' { }
	| vardcl ';' { }
	| error ';' { yyerror("***Error: illegal variable declaration\n");}  
	;

vardcl	: idlist ':' type {  
				linkedListNode * temp = $1;

				while (temp != NULL) {
					insert(temp->identifierName, NextOffset($3.size), $3.isArray);
					temp = temp->next;
				}
			  }
	;

idlist	: idlist ',' ID {
				// 1. use the child's (the child node in the parse tree) linked-list (aka $1)
				// 2. insert id.str, (aka $3.str), into the linked-list
				// 3. pass up the head node pointer to the next idlist.
				// 4. call insert
				
				linkedListNode *llnode = (linkedListNode *) malloc(sizeof(linkedListNode));
				llnode -> next = NULL;
				strcpy(llnode->identifierName, $3.str);
				insertAtEnd($1, llnode);

				// pass up head pointer

				$$ = $1;
			}
        
	| ID		{

				// this is the base case 
				// 1. create linked-list by creating a head node
				// 2. pass up the pointer to the head node (and consequently the entire linked list)
			
				linkedListNode * llnode = (linkedListNode *) malloc(sizeof(linkedListNode));
				llnode->next = NULL;
				strcpy(llnode->identifierName, $1.str);
				$$ = llnode;
			}
	;

type	: ARRAY '[' ICONST ']' OF INT {  }

        | INT {  }
	;

stmtlist : stmtlist ';' stmt { }
	| stmt { }
        | error { yyerror("***Error: ';' expected or illegal statement \n");}
	;

stmt    : ifstmt { }
	| fstmt { }
	| astmt { }
	| writestmt { }
	| cmpdstmt { }
	;

cmpdstmt: BEG stmtlist END { }
	;

ifstmt :  ifhead 
          THEN stmt 
  	  ELSE 
          stmt 
	;

ifhead : IF condexp {  }
        ;

fstmt	: FOR ctrlexp DO stmt  {  } 
	;


astmt : lhs ASG exp             { 
				  emit(NOLABEL,
                                       STORE, 
                                       $3.targetRegister,
                                       $1.targetRegister,
                                       EMPTY);
                                }
	;

lhs	: ID			{ 
					int newReg1 = NextRegister();

                                        // We have two cases: we either have the variable in the symbol table
                                        // already, or we don't
                                        // so let's use an if statement for the two cases
                                        int offset;
                                        SymTabEntry * resultOfLookUp = lookup($1.str);

                                        //the case that the variable is NOT in the table
                                        // then we need to most importantly, throw an error,
                                        // and maybe add it to the symbol table just as filler code
                                        if ( resultOfLookUp == NULL )
                                        {
                                                //throw error instead of inserting
                                                //Done : insert the proper error code
                                                printf("\n*** ERROR ***: Variable %s not declared.\n", $1.str);
                                        }
                                        else
                                        {
                                                if (resultOfLookUp -> isArray == 1) {
                                                        printf("\n*** ERROR ***: Variable %s is not a scalar variable.\n", $1.str);
                                                }

                                                //the case that the variable IS already in the table
                                                // then all we need to do is pass up the name of the token up to LHS nonterminal
                                                //so that we can look up the variable later, higher up in the parse tree,
                                                // for the sake of type checking AND knowing the offset
                                                offset = resultOfLookUp -> offset;

                                                //// Compute address of variable "i" at offset 0 in reg TODO i think this is right???????? check
                                                int printOffset = -4; /* default location for printing */
                                                sprintf(CommentBuffer, "Compute address of variable \"%s\" at offset 0 in register %d", $1.str, newReg1);
                                                emitComment(CommentBuffer);
                                                emit(NOLABEL, LOADI, offset, newReg1, EMPTY);

                                                $$.targetRegister = newReg1;

					} 
                         	  }


                                |  ID '[' exp ']' {   }
                                ;

writestmt: PRINT '(' exp ')' 	{ 
					int printOffset = -4; /* default location for printing */
  	                        sprintf(CommentBuffer, "Code for \"PRINT\" from offset %d", printOffset);
	                        emitComment(CommentBuffer);
                                emit(NOLABEL, STOREAI, $3.targetRegister, 0, printOffset);
                                emit(NOLABEL, OUTPUTAI, 0, printOffset, EMPTY);
                         	}
	;



exp	: exp '+' exp		{ int newReg = NextRegister();

                                  $$.targetRegister = newReg;
                                  emit(NOLABEL, 
                                       ADD, 
                                       $1.targetRegister, 
                                       $3.targetRegister, 
                                       newReg);
                                }

        | exp '-' exp		{ int newReg = NextRegister();

                                  $$.targetRegister = newReg;
                                  emit(NOLABEL, 
                                       SUB, 
                                       $1.targetRegister, 
                                       $3.targetRegister, 
                                       newReg);}

        | exp '*' exp		{  }


        | ID			{ /* BOGUS  - needs to be fixed */
	                          int newReg = NextRegister();
                                  int offset = NextOffset(4);

	                          $$.targetRegister = newReg;
				  emit(NOLABEL, LOADAI, 0, offset, newReg);
                                  
	                        }

        | ID '[' exp ']'	{   }
 


	| ICONST                 { int newReg = NextRegister();
	                           $$.targetRegister = newReg;
				   emit(NOLABEL, LOADI, $1.num, newReg, EMPTY); }

	| error { yyerror("***Error: illegal expression\n");}  
	;

ctrlexp	: ID ASG ICONST ',' ICONST {  }
	| error { yyerror("***Error: illegal control expression\n");}  
        ;


condexp	: exp NEQ exp		{  } 

        | exp EQ exp		{  } 

        | exp LT exp		{
					  
				}

        | exp LEQ exp		{
					/*
                                        this attribute does the ILOC code,
                                        but i still need to figure out what
                                        is necessary in terms of local information flow
                                        */

                                        int targReg = NextRegister();
                                        int register1 = $1.targetRegister;
                                        int register2 = $3.targetRegister;

                                        emit(NOLABEL, CMPLE, register1, register2, targReg);


                                        $$.targetRegister = targReg; 
				}

	| error { yyerror("***Error: illegal conditional expression\n");}  
        ;

%%

linkedListNode *insertAtEnd(linkedListNode *head, linkedListNode *lln) {
	linkedListNode * temp = NULL;

        if (head != NULL ) {
                temp = head;
                while (temp -> next != NULL) {
                        temp = temp -> next;
                }
                lln -> next = NULL;
                temp -> next = lln;
        } else {
                lln -> next = NULL;
                head = lln;
        }

        return head;
}

void yyerror(char* s) {
        fprintf(stderr,"%s\n",s);
        }


int
main(int argc, char* argv[]) {

  printf("\n     CS515 Fall 2018 Compiler\n\n");

  outfile = fopen("iloc.out", "w");
  if (outfile == NULL) { 
    printf("ERROR: cannot open output file \"iloc.out\".\n");
    return -1;
  }

  CommentBuffer = (char *) malloc(650);  
  InitSymbolTable();

  printf("1\t");
  yyparse();
  printf("\n");

  PrintSymbolTable();
  
  fclose(outfile);
  
  return 1;
}




