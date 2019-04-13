/* Bit-Serial CPU simulator
 * LICENSE: MIT
 * AUTHOR:  Richard James Howe
 * EMAIL:   howe.r.j.89@gmail.com
 * GIT:     https://github.com/howerj/bit-serial */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <assert.h>
#include <string.h>
#include <ctype.h>

#define CONFIG_TRACER_ON (1)
#define MSIZE            (4096u)
#define MAX_VARS         (256)
typedef uint16_t mw_t; /* machine word */
typedef struct { mw_t pc, acc, m[MSIZE]; } bcpu_t;

static const char *commands[] = { 
	"nop",  "halt",  "jump",    "jumpz", 
	"and",  "or",    "xor",     "invert",
	"load", "store", "literal", "11?",
	"add",  "less",  "14?",     "15?"
};

typedef struct { char name[80]; int type; mw_t value; } var_t;

static int instruction(const char *c) {
	assert(c);
	for (size_t i = 0; i < sizeof(commands) / sizeof(commands[0]); i++) {
		if (!strcmp(commands[i], c))
			return i;
	}
	return -1;
}

static var_t *lookup(var_t *vs, size_t length, const char *var) {
	assert(vs);
	assert(var);
	for (size_t i = 0; i < length; i++) {
		var_t *v = &vs[i];
		if (vs->name[0] == 0)
			return NULL;
		if (!strcmp(v->name, var))
			return v;
	}
	return NULL;
}

enum { TYPE_VAR, TYPE_LABEL };

static int add(var_t *vs, size_t length, const char *name, int type, mw_t value) {
	assert(vs);
	assert(name);
	if (lookup(vs, length, name))
		return -1;
	for (size_t i = 0; i < length; i++) {
		var_t *v = &vs[i];
		if (v->name[0] == 0) {
			strncpy(v->name, name, sizeof v->name);
			v->name[sizeof(v->name) - 1] = 0;
			v->type = type;
			v->value = value;
			return 0;
		}
	}
	return -2;
}

static int comment(const char *line) {
	for (size_t i = 0; line[i]; i++) {
		if (isspace(line[i]))
			continue;
		if (line[i] == '#')
			return 1;
	}
	return 0;
}

static int assemble(bcpu_t *b, FILE *input) {
	assert(b);
	assert(input);
	b->pc = 0;
	b->acc = 0;
	memset(b->m, 0, sizeof b->m);
	unsigned long pc = 0, data = MSIZE - 1;
	var_t *vs = calloc(sizeof *vs, MAX_VARS);
	if (!vs) {
		fprintf(stderr, "allocation failed\n");
		return -1;
	}
	for (char line[256] = { 0 }; fgets(line, sizeof line, input); memset(line, 0, sizeof line)) {
		char command[80] = { 0 }, argument[80] = { 0 };
		const int args = sscanf(line, "%79s %79s", command, argument);
		if (pc >= data) {
			fprintf(stderr, "program space full\n");
			goto fail;
		}
		if (comment(line)) {
			/* do nothing */
		} else if (args == 1) {
			fprintf(stderr, "invalid command: %s\n", line);
			goto fail;
		} else if (args == 2) {
			unsigned op1 = 0;
			const int opvalid = sscanf(argument, "$%x", &op1) == 1;
			if (op1 > 0x0FFFu) {
				fprintf(stderr, "operand too big: %x\n", op1);
				goto fail;
			}
			const int inst = instruction(command);
			if (inst < 0) {
				if (!strcmp(command, "allocate")) {
					if (!opvalid) {
						fprintf(stderr, "invalid allocate: %s\n", argument);
						goto fail;
					}
					data -= op1;
				} else if (!strcmp(command, "variable")) {
					const int added = add(vs, MAX_VARS, argument, TYPE_VAR, data--);
					if (added < 0) {
						fprintf(stderr, "variable? %d/%s\n", added, argument);
						goto fail;
					}
				} else if (!strcmp(command, "label")) {
					const int added = add(vs, MAX_VARS, argument, TYPE_LABEL, pc);
					if (added < 0) {
						fprintf(stderr, "label? %d/%s\n", added, argument);
						goto fail;
					}
				} else {
					fprintf(stderr, "unknown command: %s\n", command);
					goto fail;
				}
			} else {
				if (!opvalid) {
					var_t *v = lookup(vs, MAX_VARS, argument);
					if (!v) {
						fprintf(stderr, "invalid operand: %s\n", argument);
						goto fail;
					} else {
						op1 = v->value;
					}
				}
				b->m[pc++] = (((mw_t)inst) << 12) | op1;
			}
		}
	}
	free(vs);
	return 0;
fail:
	free(vs);
	return -1;
}

static inline int trace(bcpu_t *b, FILE *tracer, unsigned cycles, const mw_t pc, const mw_t acc, const mw_t op1, const mw_t cmd) {
	assert(b);
	if (!tracer)
		return 0;
	assert(cmd < (sizeof(commands)/sizeof(commands[0])));
	char cbuf[8] = { 0 };
	snprintf(cbuf, sizeof cbuf, "%s       ", commands[cmd]);
	return fprintf(tracer, "%4x: %4x %s %4x %4x\n", cycles, (unsigned)pc, cbuf, (unsigned)acc, (unsigned)op1);
}

static int bcpu(bcpu_t *b, FILE *in, FILE *out, FILE *tracer, const unsigned cycles) {
	assert(b);
	assert(in);
	assert(out);
	int r = 0;
	mw_t * const m = b->m, pc = b->pc, acc = b->acc;
	const unsigned forever = cycles == 0;
       	unsigned count = 0;
	for (; count < cycles || forever; count++) {
		const mw_t instr = m[pc % MSIZE];
		const mw_t op1   = instr & 0x0FFF;
		const mw_t cmd   = (instr >> 12u) & 0xFu;
		if (CONFIG_TRACER_ON)
			trace(b, tracer, count, pc, acc, op1, cmd);
		pc++;
		switch (cmd) {
		case 0x0:                        break; /* NOP     */
		case 0x1: r = 0;             goto halt; /* HALT    */
		case 0x2: pc = op1;              break; /* JUMP    */
		case 0x3: if (!(acc)) pc = op1;  break; /* JUMPZ   */

		case 0x4: acc &= op1;            break; /* AND     */
		case 0x5: acc |= op1;            break; /* OR      */
		case 0x6: acc ^= op1;            break; /* XOR     */
		case 0x7: acc = ~acc;            break; /* INVERT  */

		case 0x8: acc = m[op1 % MSIZE];  break; /* LOAD    */
		case 0x9: m[op1 % MSIZE] = acc;  break; /* STORE   */
		case 0xA: acc = op1;             break; /* LITERAL */
		/*   0xB: Reserved for memory operations           */

		case 0xC: acc += op1;            break; /* ADD      */
		case 0xD: acc  = acc < op1;      break; /* LESS     */
		/*   0xE: Reserved for arithmetic operations        */
		/*   0xF: Reserved for arithmetic operations        */
		
		default: r = -1; goto halt;
		}
	}
halt:
	b->pc  = pc;
	b->acc = acc;
	return r;
}

int main(int argc, char **argv) {
	int fail = 0;
	static bcpu_t b = { 0, 0, { 0 } };
	if (argc != 3) {
		fprintf(stderr, "usage: h|a %s file\n", argv[0]);
		return -1;
	}
	FILE *program = fopen(argv[2], "rb");
	if (!program) {
		fprintf(stderr, "could not open file for reading: %s\n", argv[2]);
		return -2;
	}
	if (!strcmp(argv[1], "h")) {
		for (size_t i = 0; i < MSIZE; i++) {
			int pc = 0;
			if (fscanf(program, "%x", &pc) != 1)
				break;
			b.m[i] = pc;
		}
	} else if(!strcmp(argv[1], "a")) {
		fail = assemble(&b, program);
	}
	fclose(program);
	if (fail)
		return 1;
	return !!bcpu(&b, stdin, stdout, stderr, 0x1000);
}
