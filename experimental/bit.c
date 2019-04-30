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
#define MAX_VARS         (4096u)
typedef uint16_t mw_t; /* machine word */
typedef struct { mw_t pc, acc, flg, shadow, count, compare, m[MSIZE]; } bcpu_t;
typedef struct { FILE *in, *out; mw_t ch, leds, switches; } bcpu_io_t;
typedef struct { char name[80]; int type; mw_t value; } var_t;
enum { TYPE_VAR, TYPE_LABEL };

static const char *commands[] = { 
	"or",   "and",   "xor",     "invert",
	"add",  "sub",   "lshift",  "rshift",
	"load", "store", "literal", "flags",
	"jump", "jumpz", "shadow",  "15?",
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

static int println(FILE *out, const char *fmt, va_list ap) {
	assert(out);
	assert(fmt);
	const int r1 = vfprintf(out, fmt, ap);
	const int r2 = fputc('\n', out);
	const int r3 = fflush(out);
	return r1 > 0 && r2 > 0 && r3 > 0 ? r1 + 1 : -1;
}

static int error(const char *fmt, ...) {
	assert(fmt);
	va_list ap;
	va_start(ap, fmt);
	println(stderr, fmt, ap);
	va_end(ap);
	return -1;
}

static void die(const char *fmt, ...) {
	assert(fmt);
	va_list ap;
	va_start(ap, fmt);
	println(stderr, fmt, ap);
	va_end(ap);
	exit(EXIT_FAILURE);
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
		error("allocation failed");
		return -1;
	}
	for (char line[256] = { 0 }; fgets(line, sizeof line, input); memset(line, 0, sizeof line)) {
		char command[80] = { 0 }, arg1[80] = { 0 }, arg2[80] = { 0 };
		skip(line);
		unsigned op0 = 0, op1 = 0, op2 = 0;
		const int args = sscanf(line, "%79s %79s %79s", command, arg1, arg2);
		const int arg0num = sscanf(command, "$%x", &op0) == 1;
		const int arg1num = sscanf(arg1,    "$%x", &op1) == 1;
		const int arg2num = sscanf(arg2,    "$%x", &op2) == 1;

		if (used >= data) {
			error("program space full");
			goto fail;
		}
		if (args <= 0) {
			/* do nothing */
		} else if (args == 1) {
			if (arg0num) {
				b->m[used++] = op0;
			} else if (!strcmp(command, "nop")) {
				assert(used < MSIZE);
				b->m[used++] = 0;
			} else if (!strcmp(command, "clr")) {
				assert(used < MSIZE);
				b->m[used++] = (instruction("literal") << 12u) | 0;
			} else if (!strcmp(command, "invert")) {
				assert(used < MSIZE);
				b->m[used++] = (instruction("invert") << 12u) | 0;
			} else {
				var_t *v = lookup(vs, MAX_VARS, command);
				if (!v) {
					error("invalid command: %s", line);
					goto fail;
				}
				b->m[used++] = v->value;
			}
		} else if (args == 2) {
			if (arg1num && op1 > 0x0FFFu) {
				error("operand too big: %x", op1);
				goto fail;
			}
			const int inst = instruction(command);
			if (inst < 0) {
				if (!strcmp(command, "allocate")) {
					if (!arg1num) {
						error("invalid allocate: %s", arg1);
						goto fail;
					}
					data -= op1;
				} else if (!strcmp(command, "variable")) {
					const int added = reference(vs, MAX_VARS, arg1, TYPE_VAR, data--, 1);
					if (added < 0) {
						error("variable? %d/%s", added, arg1);
						goto fail;
					}
				} else if (!strcmp(command, "label")) {
					const int added = reference(vs, MAX_VARS, arg1, TYPE_LABEL, used, 1);
					if (added < 0) {
						error("label? %d/%s", added, arg1);
						goto fail;
					}
				} else {
					error("unknown command: %s", command);
					goto fail;
				}
			} else {
				if (!arg1num) {
					var_t *v = lookup(vs, MAX_VARS, arg1);
					if (!v) {
						const int added = reference(unknown, MAX_VARS, arg1, TYPE_LABEL, used, 0);
						if (added < 0) {
							error("forward reference? %d/%s", added, arg1);
							goto fail;
						}
						op1 = 0; // patch later
					} else {
						op1 = v->value;
					}
				}
				assert(used < MSIZE);
				b->m[used++] = (((mw_t)inst) << 12) | op1;
			}
		} else if (args == 3) {
			if (!strcmp(command, "set")) {
				if (!arg1num) {
					var_t *v = lookup(vs, MAX_VARS, arg1);
					if (!v) {
						error("unknown variable: %s", arg1);
						goto fail;
					}
					op1 = v->value;
				}
				if (op1 > 0x0FFF) {
					error("operand too big: %x", op1);
					goto fail;
				}

				if (!arg2num) {
					var_t *v = lookup(vs, MAX_VARS, arg2);
					if (!v) {
						error("unknown variable: %s", arg2);
						goto fail;
					}
					op2 = v->value;
				}
				assert(op1 < MSIZE);
				b->m[op1] = op2;
			} else {
				error("unknown command: %s", command);
				goto fail;
			}
		} else {
			error("invalid command: \"%s\"", line);
			goto fail;
		}
	}
	const char *unknown_label = patch(b, vs, MAX_VARS, unknown, MAX_VARS);
	if (unknown_label) {
		error("invalid reference: %s", unknown_label);
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

static inline int trace(bcpu_t *b, bcpu_io_t *io, FILE *tracer, 
		unsigned cycles, const mw_t pc, const mw_t flg, 
		const mw_t acc, const mw_t op1, const mw_t cmd) {
	assert(b);
	assert(io);
	if (!tracer)
		return 0;
	assert(cmd < (sizeof(commands)/sizeof(commands[0])));
	char cbuf[8] = { 0 };
	snprintf(cbuf, sizeof cbuf - 1, "%s       ", commands[cmd]);
	return fprintf(tracer, "%4x: %4x %2x:%s %4x %4x %4x %4x\n", 
			cycles, (unsigned)pc, (unsigned)cmd, cbuf, 
			(unsigned)acc, (unsigned)op1, (unsigned)flg, 
			(unsigned)io->leds);
}

static inline unsigned bits(unsigned b) {
	unsigned r = 0;
	do if (b & 1) r++; while (b >>= 1);
	return r;
}

static inline mw_t rotl(const mw_t value, unsigned shift) {
    if (!(shift &= ((sizeof(value)*8) - 1)))
      return value;
    return (value << shift) | (value >> ((sizeof(value)*8) - shift));
}

static inline mw_t rotr(const mw_t value, unsigned shift) {
    if (!(shift &= ((sizeof(value)*8) - 1)))
      return value;
    return (value >> shift) | (value << ((sizeof(value)*8) - shift));
}

static inline mw_t shiftl(const int type, const mw_t value, unsigned shift) {
	return type ? rotl(value, shift) : value << shift;
}

static inline mw_t shiftr(const int type, const mw_t value, unsigned shift) {
	return type ? rotr(value, shift) : value >> shift;
}

static inline mw_t add(mw_t a, mw_t b, mw_t *carry) {
	assert(carry);
	const mw_t parry = !!(*carry & 1u);
	const mw_t r = a + b + parry;
	*carry &= ~1u;
	if (r < (a + parry) && r < (b + parry))
		*carry |= 1;
	return r;
}

static inline mw_t sub(mw_t a, mw_t b, mw_t *under) {
	assert(under);
	const mw_t r = a - b;
	*under &= ~2u;
	*under |= b > a;
	return r;
}

static inline void swap(mw_t *a, mw_t *b) {
	assert(a);
	assert(b);
	const mw_t c = *a;
	*a = *b;
	*b = c;
}

static inline mw_t bload(bcpu_t *b, bcpu_io_t *io, mw_t flg, mw_t addr) {
	assert(b);
	assert(io);
	addr &= 0x0FFFu;
	addr |= (!!(flg & (1u << 11))) << 15;
	if (addr & 0x8000u) { /* io */
		switch (addr & 0x7) {
		case 0: return io->switches;
		case 1: return (1u << 11u) | (io->ch & 0xFF);
		}
		return 0;
	}
	return b->m[addr % MSIZE];
}

static inline void bstore(bcpu_t *b, bcpu_io_t *io, mw_t flg, mw_t addr, mw_t val) {
	assert(b);
	assert(io);
	addr &= 0x0FFFu;
	addr |= (!!(flg & (1u << 11))) << 15;
	if (addr & 0x8000u) { /* io */
		switch (addr & 0x7) {
		case 0: io->leds = val; break;
		case 1: 
			if (val & (1u << 13))
				fputc(val & 0xFFu, io->out);
			if (val & (1u << 10))
				io->ch = fgetc(io->in);
			break;
		case 2: /* TX control */ break;
		case 3: /* RX control */ break;
		case 4: /* UART control */ break;
		}
	} else {
		b->m[addr % MSIZE] = val;
	}
}

static int bcpu(bcpu_t *b, bcpu_io_t *io, FILE *tracer, const unsigned cycles) {
	assert(b);
	assert(io);
	int r = 0;
	mw_t * const m = b->m, pc = b->pc, acc = b->acc, flg = b->flg, shadow = b->shadow, compare = b->compare, count = b->count;
	const unsigned forever = cycles == 0;
       	unsigned steps = 0;
	for (; steps < cycles || forever; steps++) {
		const mw_t instr = m[pc % MSIZE];
		const mw_t op1   = instr & 0x0FFF;
		const mw_t cmd   = (instr >> 12u) & 0xFu;
		const int alt = !!(flg & (1u << 5));
		if (CONFIG_TRACER_ON)
			trace(b, io, tracer, steps, pc, flg, acc, op1, cmd);
		if (flg & (1u << 7)) /* HALT */
			goto halt;
		if (flg & (1u << 6)) { /* RESET */
			pc = 0;
			acc = 0;
			flg = 0;
			count = 0;
			compare = 0;
		}
		flg &= 0xFFE3;      /* clear flags we are about to set */
		flg |= ((!acc) << 2);             /* set zero flag     */
		flg |= ((!!(acc & 0x8000)) << 3); /* set negative flag */
		flg |= (!(bits(acc) & 1u)) << 4;  /* set parity bit    */
		if (flg & (1u << 9)) { /* Counter Enable */
			count += 1;
		}
		if (flg & (1u << 10)) {
			if (count == compare) {
				swap(&pc, &shadow);
				continue;
			}
		}

		pc++;
		switch (cmd) {
		case 0x0: acc |= op1;                        break; /* OR      */
		case 0x1: acc &= (0xF000 | op1);             break; /* AND     */
		case 0x2: acc ^= op1;                        break; /* XOR     */
		case 0x3: acc = ~acc;                        break; /* INVERT  */

		case 0x4: acc = add(acc, op1, &flg);         break; /* ADD     */
		case 0x5: acc = sub(acc, op1, &flg);         break; /* SUB     */
		case 0x6: acc = shiftl(alt, acc, bits(op1)); break; /* LSHIFT  */
		case 0x7: acc = shiftr(alt, acc, bits(op1)); break; /* RSHIFT  */

		case 0x8: acc = bload(b, io, flg, op1);      break; /* LOAD    */
		case 0x9: bstore(b, io, flg, op1,  acc);     break; /* STORE   */
		case 0xA: acc = op1;                         break; /* LITERAL */
		case 0xB: acc = flg; flg = op1;              break; /* FLAGS   */

		case 0xC: pc = op1;                          break; /* JUMP    */
		case 0xD: if (!acc) pc = op1;                break; /* JUMPZ   */
		case 0xE: /* shadow */
			if (alt) { swap(&acc, &shadow); }
			else     { compare = acc; acc = count; }
			break;

		/*   0xF: Reserved                                             */

		default: r = -1; goto halt;
		}

	}
halt:
	b->pc  = pc;
	b->acc = acc;
	b->flg = flg;
	b->shadow = shadow;
	b->count = count;
	b->compare = compare;
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
	for (size_t i = 0; i < MSIZE; i++) /* option to save the rest of bcpu_t? */
		if (fprintf(output, "%04x\n", (unsigned)(b->m[i])) < 0)
			return -1;
	return 0;
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
	static bcpu_t b = { 0, 0, 0, 0, 0, 0, { 0 } };
	bcpu_io_t io = { .in = stdin, .out = stdout };
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
	if (run && bcpu(&b, &io, trace, cycles) < 0)
		die("running failed");
	return 0; /* dying cleans everything up */
}

