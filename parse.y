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
       	labelInfo labelINF;
	ctrlExp ctrlExpInfo;
	}

%token PROG PERIOD VAR 
%token INT BOOL PRINT THEN IF DO  
%token ARRAY OF 
%token BEG END ASG  
%token EQ NEQ LT LEQ 
%token ELSE
%token <labelINF> FOR 
%token <token> ID ICONST 

%type <labelINF> ifhead
%type <ctrlExpInfo> ctrlexp

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

        | INT { $$.isArray = 0;
                $$.size = 1; }
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

ifstmt :  ifhead {
			int label1 = NextLabel();
                        int label2 = NextLabel();
                        int label3 = NextLabel();

                        $1.labelOne = label1;
                        $1.labelTwo = label2;
                        $1.labelThree = label3;

                        emit(NOLABEL, CBR, $1.targetRegister, $1.labelOne, $1.labelTwo);
                        emit($1.labelOne, NOP, EMPTY, EMPTY, EMPTY);
		 }
          THEN stmt 
		 {
			emit(NOLABEL, BR, $1.labelThree, EMPTY, EMPTY);
                        emit($1.labelTwo, NOP, EMPTY, EMPTY, EMPTY);
		 }
  	  ELSE 
          stmt 
		 {
			emit($1.labelThree, NOP, EMPTY, EMPTY, EMPTY);
		 }
	;

ifhead : IF condexp { $$.targetRegister = $2.targetRegister; }
        ;

fstmt	: FOR   {
			int label1 = NextLabel();
                        int label2 = NextLabel();
                        int label3 = NextLabel();

                        $1.labelOne = label1;
                        $1.labelTwo = label2;
                        $1.labelThree = label3;

                        
		}
	  ctrlexp {
			int regThatHoldsValueOfInductionVariableRetirevedFromMemory = NextRegister();
			int regThatHoldsValueOfConditionalExpression = NextRegister();
	
                        //// This is the body of the for loop
                        //int printOffset = -4; /* default location for printing */
                        sprintf(CommentBuffer, "Generate control code for \"FOR\"");
                        emitComment(CommentBuffer);
			emit($1.labelOne, LOADAI, 0, $3.num, regThatHoldsValueOfInductionVariableRetirevedFromMemory);
			emit(NOLABEL, CMPLE, regThatHoldsValueOfInductionVariableRetirevedFromMemory, $3.upperBoundReg, regThatHoldsValueOfConditionalExpression);
			emit(NOLABEL, CBR, regThatHoldsValueOfConditionalExpression, $1.labelTwo, $1.labelThree);
                        emit($1.labelTwo, NOP, EMPTY, EMPTY, EMPTY);
                        // // Body of "FOR" construct starts here

                        //int printOffset = -4; /* default location for printing */
                        //sprintf(CommentBuffer, "Body of \"FOR\" construct starts here");
                        //emitComment(CommentBuffer);
		  } 
	  DO stmt  {
			int regThatHoldsValueOfInductionVariableRetirevedFromMemory = NextRegister();
			int iPlusOne = NextRegister();	

			emit(NOLABEL, LOADAI, 0, $3.num, regThatHoldsValueOfInductionVariableRetirevedFromMemory);
			emit(NOLABEL, ADDI, regThatHoldsValueOfInductionVariableRetirevedFromMemory, 1, iPlusOne);			
			emit(NOLABEL, STOREAI, iPlusOne, 0, $3.num);

			emit(NOLABEL, BR, $1.labelOne, EMPTY, EMPTY);
	                emit($1.labelThree, NOP, EMPTY, EMPTY, EMPTY);
		   } 
	;


astmt : lhs ASG exp             {
					emit(NOLABEL, STOREAO, $3.targetRegister, 0, $1.targetRegister);
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
                                                sprintf(CommentBuffer, "variable \"%s\" @ offset %d => register %d", $1.str, offset, newReg1);
                                                emitComment(CommentBuffer);
                                                emit(NOLABEL, LOADI, offset, newReg1, EMPTY);

                                                $$.targetRegister = newReg1;

					} 
                         	  }


                |  ID '[' exp ']' {
			 		int newReg1 = NextRegister();
                                        int newReg2 = NextRegister();
                                        int newReg3 = NextRegister();
                                        int newReg4 = NextRegister();
                                        int newReg5 = NextRegister();
                                        int newReg6 = NextRegister();

                                        SymTabEntry * resultOfLookup = lookup($1.str);

                                        if (resultOfLookup == NULL)
                                        {
                                                //if not in symbol table
                                                //print error
                                                printf("\n*** ERROR ***: Variable %s not declared.\n", $1.str);
                                        }
                                        else
                                        {

                                                if (resultOfLookup -> isArray == 0)
                                                {
                                                        printf("\n*** ERROR ***: Variable %s is not an array variable.\n", $1.str);
                                                        //*** ERROR ***: Variable a is not a scalar variable.\n");
                                                }

                                                int RegisterContainingOffsetFromBase = $3.targetRegister;
                                                int offsetOfBase = resultOfLookup -> offset;

                                                //// Compute address of array variable "b" with base ad
                                                int printOffset = -4; /* default location for printing */
                                                sprintf(CommentBuffer, "Compute address of array variable \"%s\" with base address %d", $1.str, offsetOfBase);
                                                emitComment(CommentBuffer);
                                                emit(NOLABEL, LOADI, 4, newReg3, EMPTY);
                                                emit(NOLABEL, MULT, RegisterContainingOffsetFromBase, newReg3, newReg1);
                                                emit(NOLABEL, LOADI, offsetOfBase, newReg6, EMPTY);
                                                emit(NOLABEL, ADD, newReg1, newReg6, newReg2);

                                                $$.targetRegister = newReg2;
					}
				}
                ;

writestmt: PRINT '(' exp ')' 	{ 
					int printOffset = -4; /* default location for printing */
  	                        	sprintf(CommentBuffer, "Code for \"PRINT\" from offset %d", printOffset);
	                        	emitComment(CommentBuffer);
                                	emit(NOLABEL, STOREAI, $3.targetRegister, 0, printOffset);
                                	emit(NOLABEL, OUTPUTAI, 0, printOffset, EMPTY);
                         	}




exp	: exp '+' exp		{ 
					int newReg = NextRegister();

                                  	$$.targetRegister = newReg;
                                  	emit(NOLABEL, ADD, $1.targetRegister, $3.targetRegister, newReg);
                                }

        | exp '-' exp		{ 
					int newReg = NextRegister();

                                  	$$.targetRegister = newReg;
                                  	emit(NOLABEL, SUB, $1.targetRegister, $3.targetRegister, newReg);
				}

        | exp '*' exp		{  
					int newReg = NextRegister();

                                  	$$.targetRegister = newReg;
                                  	emit(NOLABEL, MULT, $1.targetRegister, $3.targetRegister, newReg);
 				}


        | ID			{
					//remember to check this by running it through sim
                                        int newReg = NextRegister();

                                        SymTabEntry *resultOfLookUp = lookup($1.str);

                                        //TODO copy the error statement from his site
                                        if (resultOfLookUp == NULL)
					{
                                        	printf("\n*** ERROR ***: Variable %s not declared.\n", $1.str);
					}
					else
                                        {
                                                if (resultOfLookUp -> isArray == 1)
                                                {
                                                        printf("\n*** ERROR ***: Variable %s is not a scalar variable.\n", $1.str);
                                                }

                                                int offset = resultOfLookUp -> offset;

                                                // Load RHS value of array variable "b" with based address %d
                                                int printOffset = -4; /* default location for printing */
                                                sprintf(CommentBuffer, "Load RHS value of variable \"%s\" at offset %d", $1.str, offset);
                                                emitComment(CommentBuffer);
                                                $$.targetRegister = newReg;
                                                emit(NOLABEL, LOADAI, 0, offset, newReg);
                                         }
  
	                        }

        | ID '[' exp ']'	   {
					int newReg1 = NextRegister();
                                        int newReg2 = NextRegister();
                                        int newReg3 = NextRegister();
                                        int newReg4 = NextRegister();
                                        int newReg5 = NextRegister();

                                        SymTabEntry * resultOfLookup = lookup($1.str);

                                        if (resultOfLookup == NULL)
                                        {
                                                //if not in symbol table, then print error
                                                printf("\n*** ERROR ***: Variable %s is not a scalar variable.\n", $1.str);
                                        }
                                        else
                                        {
                                                if (resultOfLookup -> isArray == 0)
                                                {
                                                        printf("\n*** ERROR ***: Variable %s is not an array variable.\n", $1.str);
                                                                //*** ERROR ***: Variable a is not a scalar variable.\n");
                                                }

                                                int RegisterContainingOffsetFromBase = $3.targetRegister;
                                                int offsetOfBase = resultOfLookup -> offset;

                                                // Load RHS value of array variable "b" with based address %d
                                                int printOffset = -4; /* default location for printing */
                                                sprintf(CommentBuffer, "Load RHS value of array variable \"%s\" with base address %d", $1.str, offsetOfBase);
                                                emitComment(CommentBuffer);
                                                emit(NOLABEL, LOADI, 4, newReg3, EMPTY);
                                                emit(NOLABEL, MULT, RegisterContainingOffsetFromBase, newReg3, newReg1);
                                                emit(NOLABEL, LOADI, offsetOfBase, newReg5, EMPTY);
                                                emit(NOLABEL, ADD, newReg1, newReg5, newReg2);
                                                emit(NOLABEL, LOADAO, 0, newReg2, newReg4);

                                                $$.targetRegister = newReg4;
                                        }  
				   }
 


	| ICONST                   { 	int newReg = NextRegister();
	                           	$$.targetRegister = newReg;
				   	emit(NOLABEL, LOADI, $1.num, newReg, EMPTY);
				   }

	| error 		   { 	yyerror("***Error: illegal expression\n");}  
	;

ctrlexp	: ID ASG ICONST ',' ICONST {
					int offsetRegister = NextRegister();
					int lowerBoundRegister = NextRegister();
					int upperBoundRegister = NextRegister();
					//int targReg = NextRegister();
					SymTabEntry *resultOfLookUp = lookup($1.str); 
					int offset = resultOfLookUp -> offset;

					sprintf(CommentBuffer, "Initialize ind. variable \"%s\" at offset %d with lower bound value %d", $1.str, offset, $3.num);
					emitComment(CommentBuffer);			   
					
					emit(NOLABEL, LOADI, offset, offsetRegister, EMPTY);
					emit(NOLABEL, LOADI, $3.num, lowerBoundRegister, EMPTY);
					emit(NOLABEL, LOADI, $5.num, upperBoundRegister, EMPTY);
					emit(NOLABEL, STOREAO, lowerBoundRegister, 0, offsetRegister);
					
					$$.num = offset;
					$$.upperBoundReg = upperBoundRegister;

				   }
	| error { yyerror("***Error: illegal control expression\n");}  
        ;


condexp	: exp NEQ exp		{  
					int register1 = $1.targetRegister;
                                        int register2 = $3.targetRegister;
                                        int targReg = NextRegister();
					emit(NOLABEL, CMPNE, register1, register2, targReg);
                                        $$.targetRegister = targReg;
				} 

        | exp EQ exp		{  
                                        int targReg = NextRegister();
                                        int register1 = $1.targetRegister;
                                        int register2 = $3.targetRegister;

					emit(NOLABEL, CMPEQ, register1, register2, targReg);

                                        $$.targetRegister = targReg;
				} 

        | exp LT exp		{
					int targReg = NextRegister();
                                        int register1 = $1.targetRegister;
                                        int register2 = $3.targetRegister;

                                        emit(NOLABEL, CMPLT, register1, register2, targReg);

                                        $$.targetRegister = targReg; 
 
				}

        | exp LEQ exp		{
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

  outfile = fopen("iloc-mysol.out", "w");
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




