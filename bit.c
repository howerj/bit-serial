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
#include <stdarg.h>

#define CONFIG_TRACER_ON (1)
#define MSIZE            (4096u)
#define MAX_VARS         (256)
typedef uint16_t mw_t; /* machine word */
typedef struct { mw_t pc, acc, flg, m[MSIZE]; } bcpu_t;
typedef struct { char name[80]; int type; mw_t value; } var_t;
enum { TYPE_VAR, TYPE_LABEL };

static const char *commands[] = { 
	"or",   "and",   "xor",     "invert",
	"add",  "sub",   "lshift",  "rshift",
	"load", "store", "literal", "flags",
	"jump", "jumpz", "14?",    "15?",
};

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

static int reference(var_t *vs, size_t length, const char *name, int type, mw_t value, int unique) {
	assert(vs);
	assert(name);
	if (unique && lookup(vs, length, name))
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

/* return unknown name on failure, NULL on success */
static char *patch(bcpu_t *b, var_t *labels, size_t llength, var_t *patches, size_t plength) {
	assert(b);
	assert(patches);
	assert(labels);
	for (size_t i = 0; i < plength; i++) {
		var_t *patch = &patches[i];
		if (patch->name[0] == 0)
			return NULL; /* success */
		var_t *label = lookup(labels, llength, patch->name);
		if (!label || label->type != TYPE_LABEL)
			return &patch->name[0]; /* failure */
		b->m[patch->value] = (b->m[patch->value] & 0xF000u) | (label->value & 0x0FFFu);
	}
	return NULL; /* success */
}

static int skip(char *line) {
	assert(line);
	for (size_t i = 0; line[i]; i++)
		if (line[i] == ';' || line[i] == '#') {
			line[i] = '\0';
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
	unsigned long used = 0, data = MSIZE - 1;
	var_t *vs      = calloc(sizeof *vs,      MAX_VARS);
	var_t *unknown = calloc(sizeof *unknown, MAX_VARS);
	if (!vs || !unknown) {
		free(vs);
		free(unknown);
		fprintf(stderr, "allocation failed\n");
		return -1;
	}
	// TODO:
	// - Improve comments
	// - Add directive; setting variables
	// - Commands: 3 argument and 1 argument (nop/halt/invert) commands
	// - Add pseudo instructions; nop, clr, relative jumps
	// - Add calculations for lshift/rshift operand and bound checks
	for (char line[256] = { 0 }; fgets(line, sizeof line, input); memset(line, 0, sizeof line)) {
		char command[80] = { 0 }, arg1[80] = { 0 }, arg2[80] = { 0 };
		skip(line);
		const int args = sscanf(line, "%79s %79s %79s", command, arg1, arg2);
		if (used >= data) {
			fprintf(stderr, "program space full\n");
			goto fail;
		}
		if (args <= 0) {
			/* do nothing */
		} else if (args == 1) {
			fprintf(stderr, "invalid command: %s\n", line);
			goto fail;
		} else if (args == 2) {
			unsigned op1 = 0;
			const int arg1num = sscanf(arg1, "$%x", &op1) == 1;
			if (arg1num && op1 > 0x0FFFu) {
				fprintf(stderr, "operand too big: %x\n", op1);
				goto fail;
			}
			const int inst = instruction(command);
			if (inst < 0) {
				if (!strcmp(command, "allocate")) {
					if (!arg1num) {
						fprintf(stderr, "invalid allocate: %s\n", arg1);
						goto fail;
					}
					data -= op1;
				} else if (!strcmp(command, "variable")) {
					const int added = reference(vs, MAX_VARS, arg1, TYPE_VAR, data--, 1);
					if (added < 0) {
						fprintf(stderr, "variable? %d/%s\n", added, arg1);
						goto fail;
					}
				} else if (!strcmp(command, "label")) {
					const int added = reference(vs, MAX_VARS, arg1, TYPE_LABEL, used, 1);
					if (added < 0) {
						fprintf(stderr, "label? %d/%s\n", added, arg1);
						goto fail;
					}
				} else {
					fprintf(stderr, "unknown command: %s\n", command);
					goto fail;
				}
			} else {
				if (!arg1num) {
					var_t *v = lookup(vs, MAX_VARS, arg1);
					if (!v) {
						const int added = reference(unknown, MAX_VARS, arg1, TYPE_LABEL, used, 0);
						if (added < 0) {
							fprintf(stderr, "forward reference? %d/%s\n", added, arg1);
							goto fail;
						}
						op1 = 0; // patch later
					} else {
						op1 = v->value;
					}
				}
				b->m[used++] = (((mw_t)inst) << 12) | op1;
			}
		} else if (args == 3) {
		} else {
			fprintf(stderr, "invalid command: \"%s\"\n", line);
			goto fail;
		}
	}
	const char *unknown_label = patch(b, vs, MAX_VARS, unknown, MAX_VARS);
	if (unknown_label) {
		fprintf(stderr, "invalid reference: %s\n", unknown_label);
		goto fail;
	}
	free(vs);
	free(unknown);
	return 0;
fail:
	free(vs);
	free(unknown);
	return -1;
}

static inline int trace(bcpu_t *b, FILE *tracer, unsigned cycles, const mw_t pc, const mw_t flg, const mw_t acc, const mw_t op1, const mw_t cmd) {
	assert(b);
	if (!tracer)
		return 0;
	assert(cmd < (sizeof(commands)/sizeof(commands[0])));
	char cbuf[8] = { 0 };
	snprintf(cbuf, sizeof cbuf - 1, "%s       ", commands[cmd]);
	return fprintf(tracer, "%4x: %4x %2x:%s %4x %4x %4x\n", cycles, (unsigned)pc, (unsigned)cmd, cbuf, (unsigned)acc, (unsigned)op1, (unsigned)flg);
}

static inline unsigned bits(unsigned b) {
	unsigned r = 0;
	do if (b & 1) r++; while (b >>= 1);
	return r;
}

// TODO: add in previous carry
static inline mw_t add(mw_t a, mw_t b, mw_t *carry) {
	assert(carry);
	const mw_t r = a + b;
	*carry &= ~1u;
	if (r < a || r < b)
		*carry |= 1;
	return r;
}

// TODO: add in previous borrow
static inline mw_t sub(mw_t a, mw_t b, mw_t *under) {
	assert(under);
	const mw_t r = a - b;
	*under &= ~2u;
	*under |= b > a;
	return r;
}

static int bcpu(bcpu_t *b, FILE *in, FILE *out, FILE *tracer, const unsigned cycles) {
	assert(b);
	assert(in);
	assert(out);
	int r = 0;
	mw_t * const m = b->m, pc = b->pc, acc = b->acc, flg = b->flg;
	const unsigned forever = cycles == 0;
       	unsigned count = 0;
	for (; count < cycles || forever; count++) {
		const mw_t instr = m[pc % MSIZE];
		const mw_t op1   = instr & 0x0FFF;
		const mw_t cmd   = (instr >> 12u) & 0xFu;
		if (CONFIG_TRACER_ON)
			trace(b, tracer, count, pc, flg, acc, op1, cmd);
		if (flg & (1u << 4)) /* HALT */
			goto halt;
		if (flg & (1u << 5)) { /* RESET */
			pc = 0;
			acc = 0;
			flg = 0;
		}
		flg &= 0xFFF3;
		flg |= ((!acc) << 2) | ((!!(acc & 0x8000)) << 3);

		pc++;
		switch (cmd) {
		case 0x0: acc |= op1;                break; /* OR      */
		case 0x1: acc &= (0xF000 | op1);     break; /* AND     */
		case 0x2: acc ^= op1;                break; /* XOR     */
		case 0x3: acc = ~acc;                break; /* INVERT  */

		case 0x4: acc = add(acc, op1, &flg); break; /* ADD     */
		case 0x5: acc = sub(acc, op1, &flg); break; /* SUB     */
		case 0x6: acc <<= bits(op1);         break; /* LSHIFT  */
		case 0x7: acc >>= bits(op1);         break; /* RSHIFT  */

		case 0x8: acc = m[op1 % MSIZE];      break; /* LOAD    */
		case 0x9: m[op1 % MSIZE] = acc;      break; /* STORE   */
		case 0xA: acc = op1;                 break; /* LITERAL */
		case 0xB: acc = flg; flg = op1;      break; /* FLAGS */

		case 0xC: pc = op1;                  break; /* JUMP    */
		case 0xD: if (!acc) pc = op1;        break; /* JUMPZ   */
		/*   0xE: Reserved                                     */
		/*   0xF: Reserved                                     */

		default: r = -1; goto halt;
		}
	}
halt:
	b->pc  = pc;
	b->acc = acc;
	b->flg = flg;
	return r;
}

static int load(bcpu_t *b, FILE *input) {
	assert(b);
	assert(input);
	for (size_t i = 0; i < MSIZE; i++) {
		int pc = 0;
		if (fscanf(input, "%x", &pc) != 1)
			break;
		b->m[i] = pc;
	}
	return 0;
}

static int save(bcpu_t *b, FILE *output) {
	assert(b);
	assert(output);
	for (size_t i = 0; i < MSIZE; i++)
		if (fprintf(output, "%04x\n", (unsigned)(b->m[i])) < 0)
			return -1;
	return 0;
}

static void die(const char *fmt, ...) {
	assert(fmt);
	va_list ap;
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	fputc('\n', stderr);
	fflush(stderr);
	va_end(ap);
	exit(EXIT_FAILURE);
}

static FILE *fopen_or_die(const char *file, const char *mode) {
	assert(file);
	assert(mode);
	FILE *r = fopen(file, mode);
	if (!r)
		die("unable to open file \"%s\" (mode = %s)", file, mode);
	return r;
}

int main(int argc, char **argv) {
	int compile = 0, run = 0, cycles = 0x1000;
	static bcpu_t b = { 0, 0, 0, { 0 } };
	FILE *program = stdin, *trace = stderr, *hex = NULL;
	if (argc < 2)
		die("usage: %s -trashf input? out.hex?", argv[0]);
	if (argc >= 3)
		program = fopen_or_die(argv[2], "rb");
	if (argc >= 4)
		hex     = fopen_or_die(argv[3], "wb");
	for (size_t i = 0; argv[1][i]; i++)
		switch (argv[1][i]) {
		case '-':                   break;
		case 't': trace   = stderr; break;
		case 'r': run     = 1;      break;
		case 'a': compile = 1;      break;
		case 's': trace   = NULL;   break;
		case 'h': compile = 0;      break;
		case 'f': cycles  = 0;      break;
		default:  die("invalid option -- %c", argv[1][i]);
		}
	if ((compile ? assemble(&b, program) : load(&b, program)) < 0)
			die("loading hex file failed");
	if (hex && save(&b, hex) < 0)
		die("saving file failed");
	if (run && bcpu(&b, stdin, stdout, trace, cycles) < 0)
		die("running failed");
	return 0; /* dying cleans everything up */
}

