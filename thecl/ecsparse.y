/*
 * Redistribution and use in source and binary forms, with
 * or without modification, are permitted provided that the
 * following conditions are met:
 *
 * 1. Redistributions of source code must retain this list
 *    of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce this
 *    list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the
 *    distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
 * CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
 * PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 * OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
 * DAMAGE.
 */
%{
#include <config.h>
#include <errno.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "expr.h"
#include "file.h"
#include "list.h"
#include "program.h"
#include "thecl.h"
#include "value.h"

typedef struct {
    char* text;
} string_t;

static list_t* string_list_add(list_t* list, char* text);
static void string_list_free(list_t* list);

static thecl_instr_t* instr_new(parser_state_t* state, unsigned int id, const char* format, ...);
static thecl_instr_t* instr_new_list(parser_state_t* state, unsigned int id, list_t* list);
static void instr_add(thecl_sub_t* sub, thecl_instr_t* instr);

enum expression_type {
    EXPRESSION_OP,
    EXPRESSION_VAL,
};

typedef struct expression_t {
    /* Operator or value. */
    enum expression_type type;
    int id;
    /* For values: The value. */
    thecl_param_t* value;
    /* For operators: The child expressions. */
    list_t children;
    /* Resulting type of expression. */
    int result_type;
} expression_t;

static int parse_rank(const parser_state_t* state, const char* value);

static expression_t* expression_load_new(const parser_state_t* state, thecl_param_t* value);
static expression_t* expression_operation_new(const parser_state_t* state, const int* symbols, expression_t** operands);
static expression_t* expression_address_operation_new(const parser_state_t* state, const int* symbols, thecl_param_t* value);
static void expression_output(parser_state_t* state, expression_t* expr);
static void expression_free(expression_t* expr);
#define EXPR_22(a, b, A, B) \
    expression_operation_new(state, (int[]){ a, b, 0 }, (expression_t*[]){ A, B, NULL })
#define EXPR_12(a, A, B) \
    expression_operation_new(state, (int[]){ a, 0 }, (expression_t*[]){ A, B, NULL })
#define EXPR_11(a, A) \
    expression_operation_new(state, (int[]){ a, 0 }, (expression_t*[]){ A, NULL })
#define EXPR_1A(a, A) \
    expression_address_operation_new(state, (int[]){ a, 0 }, A)

/* Bison things. */
void yyerror(parser_state_t*, const char*);
int yylex(void);
extern FILE* yyin;

/* Parser APIs. */

/* Starts a new subroutine. */
static void sub_begin(parser_state_t* state, char* name);
/* Closes the current subroutine. */
static void sub_finish(parser_state_t* state);

/* Creates a new variable in the specified subroutine. */
static void var_create(thecl_sub_t* sub, const char* name);
/* Returns the stack offset of a specified variable in the specified sub. */
static int var_find(parser_state_t* state, thecl_sub_t* sub, const char* name);
/* Stores a new label in the current subroutine pointing to the current offset. */
static void label_create(parser_state_t* state, char* label);

/* Update the current time label. */
void set_time(parser_state_t* state, int new_time);

%}

%error-verbose
%locations
%parse-param {parser_state_t* state}

%union {
    /* Values from Flex: */
    int integer;
    float floating;
    char* string;
    struct {
        unsigned int length;
        unsigned char* data;
    } bytes;

    /* Internal types: */
    struct thecl_param_t* param;
    struct expression_t* expression;
    struct list_t* list;
}

%token <integer> INSTRUCTION "instruction"
%token <string> IDENTIFIER "identifier"
%token <string> TEXT "text"
%token <integer> INTEGER "integer"
%token <floating> FLOATING "float"
%token <string> RANK "rank"
%token COMMA ","
%token COLON ":"
%token SEMICOLON ";"
%token SQUARE_OPEN "["
%token SQUARE_CLOSE "]"
%token CAST_INTEGER "_S"
%token CAST_FLOATING "_f"
%token CAST_II "_SS"
%token CAST_IF "_Sf"
%token CAST_FF "_ff"
%token CAST_FI "_fS"
%token ANIM "anim"
%token ECLI "ecli"
%token SUB "sub"
%token VAR "var"
%token LOCAL "local"
%token AT "@"
%token BRACE_OPEN "{"
%token BRACE_CLOSE "}"
%token PARENTHESIS_OPEN "("
%token PARENTHESIS_CLOSE ")"
%token ILLEGAL_TOKEN "illegal token"
%token END_OF_FILE 0 "end of file"

%token GOTO "goto"
%token UNLESS "unless"
%token IF "if"
%token LOAD
%token LOADI
%token LOADF
%token ASSIGN "="
%token ASSIGNI "$="
%token ASSIGNF "%="
%token ADD "+"
%token ADDI "$+"
%token ADDF "%+"
%token SUBTRACT "-"
%token SUBTRACTI "$-"
%token SUBTRACTF "%-"
%token MULTIPLY "*"
%token MULTIPLYI "$*"
%token MULTIPLYF "%*"
%token DIVIDE "/"
%token DIVIDEI "$/"
%token DIVIDEF "%/"
%token MODULO "%"
%token EQUAL "=="
%token EQUALI "$=="
%token EQUALF "%=="
%token INEQUAL "!="
%token INEQUALI "$!="
%token INEQUALF "%!="
%token LT "<"
%token LTI "$<"
%token LTF "%<"
%token LTEQ "<="
%token LTEQI "$<="
%token LTEQF "%<="
%token GT ">"
%token GTI "$>"
%token GTF "%>"
%token GTEQ ">="
%token GTEQI "$>="
%token GTEQF "%>="
%token NOT "!"
%token AND "&&"
%token OR "||"
%token XOR "^"
%token DEC "--"

%token DOLLAR "$"

%type <list> Text_Semicolon_List
%type <list> Optional_Identifier_Whitespace_List
%type <list> Identifier_Whitespace_List
%type <list> Instruction_Parameters_List
%type <list> Instruction_Parameters
%type <list> Integer_List

%type <expression> Expression

%type <param> Instruction_Parameter
%type <param> Address
%type <param> Address_Type
%type <param> Integer
%type <param> Floating
%type <param> Text
%type <param> Label
%type <param> Load_Type
%type <param> Cast_Type

%type <integer> Cast_Target
%type <integer> Cast_Target2

%nonassoc ADD ADDI ADDF SUBTRACT SUBTRACTI SUBTRACTF MULTIPLY MULTIPLYI MULTIPLYF DIVIDE DIVIDEI DIVIDEF EQUAL EQUALI EQUALF INEQUAL INEQUALI INEQUALF LT LTI LTF LTEQ LTEQI LTEQF GT GTI GTF GTEQ GTEQI GTEQF MODULO OR AND XOR
%left NOT
%right DEC

%%

Statements:
    | Statement Statements
    ;

Statement:
      "sub" IDENTIFIER {
        sub_begin(state, $2);
        free($2);
      }
      "(" Optional_Identifier_Whitespace_List ")" {
            state->current_sub->arity = 0;
            if ($5 && !list_empty($5)) {
                string_t* str;
                list_for_each($5, str) {
                    state->current_sub->arity++;
                    var_create(state->current_sub, str->text);
                }
                string_list_free($5);
            }
            state->current_sub->stack = state->current_sub->arity * 4;
      }
      "{" Subroutine_Body "}" {
        sub_finish(state);
      }
    | "anim" "{" Text_Semicolon_List "}" {
        string_t* str;
        list_for_each($3, str) {
            state->ecl->anim_count++;
            state->ecl->anim_names = realloc(state->ecl->anim_names, state->ecl->anim_count * sizeof(char*));
            state->ecl->anim_names[state->ecl->anim_count - 1] = strdup(str->text);
        }
        string_list_free($3);
      }
    | "ecli" "{" Text_Semicolon_List "}" {
        string_t* str;
        list_for_each($3, str) {
            state->ecl->ecli_count++;
            state->ecl->ecli_names = realloc(state->ecl->ecli_names, state->ecl->ecli_count * sizeof(char*));
            state->ecl->ecli_names[state->ecl->ecli_count - 1] = strdup(str->text);
        }
        string_list_free($3);
      }
    | "local" IDENTIFIER "{" Integer_List "}" {
        size_t data_length = 0;
        thecl_local_data_t* local_data;
        thecl_param_t* param;

        list_for_each($4, param) {
            ++data_length;
        }

        local_data = malloc(sizeof(thecl_local_data_t) + data_length);
        local_data->data_length = data_length;
        strcpy(local_data->name, $2);
        data_length = 0;
        list_for_each($4, param) {
            local_data->data[data_length++] = param->value.val.S;
        }

        list_append_new(&state->ecl->local_data, local_data);

        list_for_each($4, param)
            free(param);
        list_free_nodes($4);
        free($4);

        free($2);
      }
    ;

Integer_List:
      Integer {
        $$ = list_new();
        list_append_new($$, $1);
      }
    | Integer_List Integer {
        $$ = $1;
        list_append_new($$, $2);
      }
    ;

Subroutine_Body:
    | "var" Optional_Identifier_Whitespace_List ";" {
        size_t var_list_length = 0;
        string_t* str;

        if ($2) {
            list_for_each($2, str) {
                ++var_list_length;
                var_create(state->current_sub, str->text);
            }
            string_list_free($2);
        }

        state->current_sub->stack += var_list_length * 4;

        instr_add(state->current_sub, instr_new(state, 40, "S", state->current_sub->stack));
      }
      Instructions
    | Instructions
    ;

Optional_Identifier_Whitespace_List:
      { $$ = NULL; }
    | Identifier_Whitespace_List
    ;

Identifier_Whitespace_List:
      IDENTIFIER {
        $$ = list_new();
        string_list_add($$, $1);
      }
    | Identifier_Whitespace_List IDENTIFIER {
        $$ = string_list_add($1, $2);
      }
    ;

Text_Semicolon_List:
      TEXT ";" {
        $$ = list_new();
        string_list_add($$, $1);
      }
    | Text_Semicolon_List TEXT ";" {
        $$ = string_list_add($1, $2);
      }
    ;

Instructions:
      Instruction ";"
    | INTEGER ":" { set_time(state, $1); }
    | Instructions INTEGER ":" { set_time(state, $2); }
    | Instructions IDENTIFIER ":" { label_create(state, $2); free($2); }
    | Instructions Instruction ";"
    | RANK { state->instr_rank = parse_rank(state, $1); } Instruction ";"
    | Instructions RANK { state->instr_rank = parse_rank(state, $2); } Instruction ";"
    ;

    /* TODO: Check the given parameters against the parameters expected for the
     *       instruction. */
Instruction:
      IDENTIFIER "(" Instruction_Parameters ")" {
        expression_t* expr;
        list_for_each(&state->expressions, expr) {
            expression_output(state, expr);
            expression_free(expr);
        }
        list_free_nodes(&state->expressions);

        eclmap_entry_t* ent = eclmap_find(g_eclmap_opcode, $1);
        if(!ent) {
            yyerror(state, "unknown mnemonic");
        }
        else {
            instr_add(state->current_sub, instr_new_list(state, ent->opcode, $3));
        }

        free($3);
      }
    | INSTRUCTION "(" Instruction_Parameters ")" {
        expression_t* expr;
        list_for_each(&state->expressions, expr) {
            expression_output(state, expr);
            expression_free(expr);
        }
        list_free_nodes(&state->expressions);

        instr_add(state->current_sub, instr_new_list(state, $1, $3));

        free($3);
      }
    | "if" Expression "goto" Label "@" Integer {
        const expr_t* expr = expr_get_by_symbol(state->version, IF);
        expression_output(state, $2);
        expression_free($2);
        instr_add(state->current_sub, instr_new(state, expr->id, "pp", $4, $6));
      }
    | "unless" Expression "goto" Label "@" Integer {
        const expr_t* expr = expr_get_by_symbol(state->version, UNLESS);
        expression_output(state, $2);
        expression_free($2);
        instr_add(state->current_sub, instr_new(state, expr->id, "pp", $4, $6));
      }
    | "goto" Label "@" Integer {
        const expr_t* expr = expr_get_by_symbol(state->version, GOTO);
        instr_add(state->current_sub, instr_new(state, expr->id, "pp", $2, $4));
      }
    | Address "=" Expression {
        const expr_t* expr = expr_get_by_symbol(state->version, $1->type == 'S' ? ASSIGNI : ASSIGNF);
        expression_output(state, $3);
        expression_free($3);
        instr_add(state->current_sub, instr_new(state, expr->id, "p", $1));
      }
    | Expression {
        expression_output(state, $1);
        expression_free($1);
      }
    ;

Instruction_Parameters:
      { $$ = NULL; }
    | Instruction_Parameters_List
    ;

Instruction_Parameters_List:
      Instruction_Parameter {
        $$ = list_new();
        list_append_new($$, $1);
      }
    | Instruction_Parameters_List "," Instruction_Parameter {
        $$ = $1;
        list_append_new($$, $3);
      }
    ;

Cast_Target2:
      CAST_II { $$ = 0x6969; }
    | CAST_IF { $$ = 0x6966; }
    | CAST_FF { $$ = 0x6666; }
    | CAST_FI { $$ = 0x6669; }

Cast_Target:
      CAST_INTEGER  { $$ = 'S'; }
    | CAST_FLOATING { $$ = 'f'; }

Cast_Type:
      Address
    | Integer
    | Floating
    | "(" Expression ")" {
        list_prepend_new(&state->expressions, $2);

        $$ = param_new($2->result_type);
        $$->stack = 1;
        $$->is_expression_param = $2->result_type;
        if ($2->result_type == 'S') {
            $$->value.val.S = -1;
        } else {
            $$->value.val.f = -1.0f;
        }
      }
    ;

Instruction_Parameter:
      Address
    | Integer
    | Floating
    | Text
    | Label
    | Cast_Target2 Cast_Type {
        $$ = param_new('D');
        $$->stack = $2->stack;
        $$->is_expression_param = $2->is_expression_param;
        $$->value.type = 'm';
        $$->value.val.m.length = 2 * sizeof(int32_t);
        $$->value.val.m.data = malloc(2 * sizeof(int32_t));
        int32_t* D = (int32_t*)$$->value.val.m.data;
        D[0] = $1;
        if ($2->type == 'f') {
            memcpy(&D[1], &$2->value.val.f, sizeof(float));
        } else {
            D[1] = $2->value.val.S;
        }
        param_free($2);
      }
    | Cast_Target "(" Expression ")" {
        list_prepend_new(&state->expressions, $3);

        $$ = param_new($1);
        $$->stack = 1;
        $$->is_expression_param = $1;
        if ($1 == 'S') {
            $$->value.val.S = -1;
        } else {
            $$->value.val.f = -1.0f;
        }
      }
    ;

Expression:
      Load_Type                      { $$ = expression_load_new(state, $1); }
    |             "(" Expression ")" { $$ = $2; }
    | Cast_Target "(" Expression ")" { $$ = $3; $$->result_type = $1; }
    | Expression "+"   Expression { $$ = EXPR_22(ADDI,      ADDF,      $1, $3); }
    | Expression "-"   Expression { $$ = EXPR_22(SUBTRACTI, SUBTRACTF, $1, $3); }
    | Expression "*"   Expression { $$ = EXPR_22(MULTIPLYI, MULTIPLYF, $1, $3); }
    | Expression "/"   Expression { $$ = EXPR_22(DIVIDEI,   DIVIDEF,   $1, $3); }
    | Expression "%"   Expression { $$ = EXPR_12(MODULO,               $1, $3); }
    | Expression "=="  Expression { $$ = EXPR_22(EQUALI,    EQUALF,    $1, $3); }
    | Expression "!="  Expression { $$ = EXPR_22(INEQUALI,  INEQUALF,  $1, $3); }
    | Expression "<"   Expression { $$ = EXPR_22(LTI,       LTF,       $1, $3); }
    | Expression "<="  Expression { $$ = EXPR_22(LTEQI,     LTEQF,     $1, $3); }
    | Expression ">"   Expression { $$ = EXPR_22(GTI,       GTF,       $1, $3); }
    | Expression ">="  Expression { $$ = EXPR_22(GTEQI,     GTEQF,     $1, $3); }
    | "!" Expression              { $$ = EXPR_11(NOT,                  $2); }
    | Expression "||"  Expression { $$ = EXPR_12(OR,                   $1, $3); }
    | Expression "&&"  Expression { $$ = EXPR_12(AND,                  $1, $3); }
    | Expression "^"   Expression { $$ = EXPR_12(XOR,                  $1, $3); }
    | Address "--"                { $$ = EXPR_1A(DEC,                  $1); }
    ;

Address:
      "[" Address_Type "]" {
        $$ = $2;
        $$->stack = 1;
      }
    | "$" IDENTIFIER {
        $$ = param_new('S');
        $$->stack = 1;
        $$->value.val.S = var_find(state, state->current_sub, $2);
        free($2);
      }
    | "%" IDENTIFIER {
        $$ = param_new('f');
        $$->stack = 1;
        $$->value.val.f = var_find(state, state->current_sub, $2);
        free($2);
      }
    ;

Address_Type:
      Integer
    | Floating
    ;

Integer:
    INTEGER {
        $$ = param_new('S');
        $$->value.val.S = $1;
      }
    ;

Floating:
    FLOATING {
        $$ = param_new('f');
        $$->value.val.f = $1;
      }
    ;

Text:
    TEXT {
        $$ = param_new('z');
        $$->value.val.z = $1;
      }
    ;

Label:
    IDENTIFIER {
        $$ = param_new('o');
        $$->value.type = 'z';
        $$->value.val.z = $1;
      }
    ;

Load_Type:
      Address
    | Integer
    | Floating
    ;

%%

static list_t*
string_list_add(
    list_t* list,
    char* text)
{
    string_t* s = malloc(sizeof(string_t));
    s->text = text;
    list_append_new(list, s);
    return list;
}

static void
string_list_free(
    list_t* list)
{
    string_t* s;
    list_for_each(list, s) {
        free(s->text);
        free(s);
    }
    list_free_nodes(list);
    free(list);
}

static thecl_instr_t*
instr_init(
    parser_state_t* state)
{
    thecl_instr_t* instr = thecl_instr_new();
    instr->time = state->instr_time;
    instr->rank = state->instr_rank;
    return instr;
}

static void
instr_set_types(
    parser_state_t* state,
    thecl_instr_t* instr)
{
    const char* format = state->instr_format(state->version, instr->id);

    thecl_param_t* param;
    list_for_each(&instr->params, param) {
        int new_type;
        /* XXX: How to check for errors?
         * Perhaps some kind of function that returns a list of satisfying types?
         * Or should there only be one type? */
        /* TODO: Implement * and ? if needed. */
        if (*format == '*')
            new_type = *(format + 1);
        else
            new_type = *format;

        if (new_type != param->type &&
            !(param->type == 'z' && (new_type == 'm' || new_type == 'x')) &&
            !(param->type == 'S' && new_type == 's')) {

            fprintf(stderr, "%s:instr_set_types: in sub %s: wrong argument type for opcode %d (expected: %c, got: %c)\n", argv0, state->current_sub->name, instr->id, new_type, param->type);
        }

        param->type = new_type;

        if (*format != '*')
            ++format;
    }

    return;
}

static thecl_instr_t*
instr_new(
    parser_state_t* state,
    unsigned int id,
    const char* format,
    ...)
{
    va_list ap;
    thecl_instr_t* instr = instr_init(state);
    instr->id = id;

    va_start(ap, format);
    while (*format) {
        thecl_param_t* param;
        if (*format == 'p') {
            param = va_arg(ap, thecl_param_t*);
        } else if (*format == 'S') {
            param = param_new('S');
            param->value.val.S = va_arg(ap, int32_t);
        } else {
            param = NULL;
        }
        list_append_new(&instr->params, param);
        ++instr->param_count;
        ++format;
    }
    va_end(ap);

    instr_set_types(state, instr);

    instr->size = state->instr_size(state->version, instr);

    return instr;
}

static thecl_instr_t*
instr_new_list(
    parser_state_t* state,
    unsigned int id,
    list_t* list)
{
    thecl_instr_t* instr = instr_init(state);
    thecl_param_t* param;

    instr->id = id;
    if (list) {
        int param_id = -1;
        if(state->uses_stack_offsets)
            list_for_each(list, param) if(param->is_expression_param) {
                if(param->value.type == 'S') {
                    param->value.val.S = param_id;
                } else if(param->value.type == 'f') {
                    param->value.val.f = param_id;
                } else if(param->value.type == 'D') {
                    int32_t* D = (int32_t*) param->value.val.m.data;
                    if (param->is_expression_param == 'S') {
                        D[1] = param_id;
                    } else {
                        float as_float = param_id;
                        memcpy(&D[1], &as_float, sizeof(float));
                    }
                }
                param_id--;
            }
        list_for_each(list, param) {
            ++instr->param_count;
            list_append_new(&instr->params, param);
        }
        list_free_nodes(list);
    }

    instr_set_types(state, instr);

    instr->size = state->instr_size(state->version, instr);

    return instr;
}

static void
instr_add(
    thecl_sub_t* sub,
    thecl_instr_t* instr)
{
    list_append_new(&sub->instrs, instr);
    instr->offset = sub->offset;
    sub->offset += instr->size;
}

static bool
check_rank_flag(
    const parser_state_t* state,
    const char* value,
    char flag)
{
    int count = 0;
    for (int i=0; value[i]; i++) if(value[i] == flag) count++;

    if (count == 0) return false;
    else if(count == 1) return true;
    else {
        fprintf(stderr, "%s:check_rank_flag: in sub %s: duplicate rank flag %c in '%s'\n", argv0, state->current_sub->name, flag, value);
        return true;
    }
}

static int
parse_rank(
    const parser_state_t* state,
    const char* value)
{
    int rank = state->has_overdrive_difficulty ? 0xC0 : 0xF0;

    if (check_rank_flag(state, value, '*')) {
        if (strlen(value) != 1) 
            fprintf(stderr, "%s:parse_rank: in sub %s: * should not be used with other rank flags.\n", argv0, state->current_sub->name);
        return 0xFF;
    } else if (check_rank_flag(state, value, '-')) {
        if (strlen(value) != 1) 
            fprintf(stderr, "%s:parse_rank: in sub %s: - should not be used with other rank flags.\n", argv0, state->current_sub->name);
        return rank;
    } else {
        if (check_rank_flag(state, value, 'E')) rank |= RANK_EASY;
        if (check_rank_flag(state, value, 'N')) rank |= RANK_NORMAL;
        if (check_rank_flag(state, value, 'H')) rank |= RANK_HARD;
        if (check_rank_flag(state, value, 'L')) rank |= RANK_LUNATIC;

        if (state->has_overdrive_difficulty) {
          if (check_rank_flag(state, value, 'X')) rank |= RANK_EXTRA;
          if (check_rank_flag(state, value, 'O')) rank |= RANK_OVERDRIVE;
        } else {
          if (check_rank_flag(state, value, '4')) rank &= ~RANK_ID_4;
          if (check_rank_flag(state, value, '5')) rank &= ~RANK_ID_5;
        }

        if (check_rank_flag(state, value, '6')) rank &= ~RANK_ID_6;
        if (check_rank_flag(state, value, '7')) rank &= ~RANK_ID_7;

        if (state->has_overdrive_difficulty && (check_rank_flag(state, value, '4') || check_rank_flag(state, value, '5')))
            fprintf(stderr, "%s:parse_rank: in sub %s: Rank flags 4 and 5 are not used in TH13+. Use X for extra, and O for overdrive instead.\n",
                    argv0, state->current_sub->name);
        if (!state->has_overdrive_difficulty && (check_rank_flag(state, value, 'X') || check_rank_flag(state, value, 'O')))
            fprintf(stderr, "%s:parse_rank: in sub %s: Rank flags X and O do not exist before TH13. Use 4 and 5 for the unused difficulties flags instead.\n",
                    argv0, state->current_sub->name);
        if (check_rank_flag(state, value, 'W') || check_rank_flag(state, value, 'Y') || check_rank_flag(state, value, 'Z'))
            fprintf(stderr, "%s:parse_rank: in sub %s: Rank flags W, X, Y and Z no longer refer to unused difficulties 4-7. %s\n",
                    argv0, state->current_sub->name,
                    state->has_overdrive_difficulty ? "In TH13+, use 6 and 7 for the remaining two unused difficulties, X for extra, and O for overdrive."
                                                    : "Before TH13, use 4, 5, 6, and 7 to refer to the unused difficulties.");

        return rank;
    }
}

static expression_t*
expression_load_new(
    const parser_state_t* state,
    thecl_param_t* value)
{
    expression_t* ret = malloc(sizeof(expression_t));
    const expr_t* expr = expr_get_by_symbol(state->version, value->type == 'S' ? LOADI : LOADF);
    ret->type = EXPRESSION_VAL;
    ret->id = expr->id;
    ret->value = value;
    ret->result_type = value->type;
    return ret;
}

static expression_t*
expression_address_operation_new(
    const parser_state_t* state,
    const int* symbols,
    thecl_param_t* value)
{
    for (; *symbols; ++symbols) {
        const expr_t* expr = expr_get_by_symbol(state->version, *symbols);

        if (value->type != expr->param_format[0])
            continue;

        expression_t* ret = malloc(sizeof(expression_t));
        ret->type = EXPRESSION_VAL;
        ret->id = expr->id;
        ret->value = value;
        ret->result_type = expr->return_type;

        return ret;
    }

    return NULL;
}

static expression_t*
expression_operation_new(
    const parser_state_t* state,
    const int* symbols,
    expression_t** operands)
{
    for (; *symbols; ++symbols) {
        const expr_t* expr = expr_get_by_symbol(state->version, *symbols);

        for (size_t s = 0; s < expr->stack_arity; ++s)
            if (operands[s]->result_type != expr->stack_formats[s])
                goto continue_outer;

        expression_t* ret = malloc(sizeof(expression_t));
        ret->type = EXPRESSION_OP;
        ret->id = expr->id;
        ret->value = NULL;
        list_init(&ret->children);
        for (size_t o = 0; o < expr->stack_arity; ++o) {
            list_append_new(&ret->children, operands[o]);
        }
        ret->result_type = expr->return_type;

        return ret;

        continue_outer: ;
    }

    return NULL;
}

static void
expression_output(
    parser_state_t* state,
    expression_t* expr)
{
    if (expr->type == EXPRESSION_VAL) {
        instr_add(state->current_sub, instr_new(state, expr->id, "p", expr->value));
    } else if (expr->type == EXPRESSION_OP) {
        expression_t* child_expr;
        list_for_each(&expr->children, child_expr) {
            expression_output(state, child_expr);
        }

        instr_add(state->current_sub, instr_new(state, expr->id, ""));
    }
}

static void
expression_free(
    expression_t* expr)
{
    expression_t* child_expr;
    if (expr->type == EXPRESSION_OP) {
        list_for_each(&expr->children, child_expr)
            expression_free(child_expr);
        list_free_nodes(&expr->children);
    }
    free(expr);
}

static void
sub_begin(
    parser_state_t* state,
    char* name)
{
    thecl_sub_t* sub = malloc(sizeof(thecl_sub_t));

    sub->name = strdup(name);
    list_init(&sub->instrs);
    sub->stack = 0;
    sub->arity = 0;
    sub->var_count = 0;
    sub->vars = NULL;
    sub->offset = 0;
    list_init(&sub->labels);

    // Touhou expects the list of subs to be sorted by name.
    thecl_sub_t* iter_sub;
    list_for_each(&state->ecl->subs, iter_sub) {
        int diff = strcmp(name, iter_sub->name);
        if(diff == 0) {
            char buf[256];
            snprintf(buf, 256, "duplicate sub: %s", name);
            yyerror(state, buf);
            break;
        } else if(diff < 0) {
            list_prepend_to(&state->ecl->subs, sub, node);
            goto no_append;
        }
    }
    list_append_new(&state->ecl->subs, sub);
no_append:

    ++state->ecl->sub_count;
    state->instr_time = 0;
    state->instr_rank = 0xff;
    state->current_sub = sub;
}

static void
sub_finish(
    parser_state_t* state)
{
    state->current_sub = NULL;
}

static void
var_create(
    thecl_sub_t* sub,
    const char* name)
{
    ++sub->var_count;
    sub->vars = realloc(sub->vars, sub->var_count * sizeof(char*));
    sub->vars[sub->var_count - 1] = strdup(name);
}

static int
var_find(
    parser_state_t* state,
    thecl_sub_t* sub,
    const char* name)
{
    // TODO: Check if a local is shadowed by a global.

    eclmap_entry_t* ent = eclmap_find(g_eclmap_global, name);
    if (ent) return ent->opcode;

    char buf[256];
    unsigned int i;
    for (i = 0; i < sub->var_count; ++i) {
        if (strcmp(name, sub->vars[i]) == 0)
            return i * 4;
    }
    snprintf(buf, 256, "variable not found: %s", name);
    yyerror(state, buf);
    return 0;
}

static void
label_create(
    parser_state_t* state,
    char* name)
{
    thecl_label_t* label = malloc(sizeof(thecl_label_t) + strlen(name) + 1);
    list_prepend_new(&state->current_sub->labels, label);
    label->offset = state->current_sub->offset;
    strcpy(label->name, name);
}

void
set_time(
    parser_state_t* state,
    int new_time)
{
    if (new_time == state->instr_time || (state->instr_time > 0 && new_time < state->instr_time)) {
        char buf[256];
        snprintf(buf, 256, "illegal timer change: %d to %d", state->instr_time, new_time);
        yyerror(state, buf);
    }
    state->instr_time = new_time;
}

void
yyerror(
    parser_state_t* state,
    const char* str)
{
    /* TODO: Research standard row and column range formats. */
    if (yylloc.first_line == yylloc.last_line) {
        if (yylloc.first_column == yylloc.last_column) {
            fprintf(stderr,
                    "%s:%s:%d,%d: %s\n",
                    argv0, current_input,
                    yylloc.first_line, yylloc.first_column, str);
        } else {
            fprintf(stderr,
                    "%s:%s:%d,%d-%d: %s\n",
                    argv0, current_input, yylloc.first_line,
                    yylloc.first_column, yylloc.last_column, str);
        }
    } else {
        fprintf(stderr,
                "%s:%s:%d,%d-%d,%d: %s\n",
                argv0, current_input, yylloc.first_line,
                yylloc.first_column, yylloc.last_line, yylloc.last_column, str);
    }
}
