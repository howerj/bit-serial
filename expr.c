/**@brief   Small Expression Evaluator
 * @license MIT
 * @author Richard James Howe
 * See: <https://en.wikipedia.org/wiki/Shunting-yard_algorithm>
 *
 * TODO:
 * - Turn into small library
 * - Add min, max, abs, sqrt, ...
 * - Add to <https://github.com/howerj/q>
 * - Add to <https://github.com/howerj/picol>
 * - Add to assembler for <https://github.com/howerj/bit-serial> */

#include <assert.h>
#include <ctype.h>
#include <limits.h>
#include <math.h> /* Not needed if USE_FLOAT == 0 */
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define BUILD_BUG_ON(condition) ((void)sizeof(char[1 - 2*!!(condition)]))
#define UNUSED(X)               ((void)(X))
#define USE_FLOAT               (0)
#define MAX_ID                  (32)
#define MAX_ERROR               (256)
#define DEFAULT_STACK_SIZE      (64)
#define implies(X, Y)           assert(!(X) || (Y))

#if USE_FLOAT == 0
typedef int number_t;
#else
typedef double number_t;
#endif

enum { ASSOCIATE_NONE, ASSOCIATE_LEFT, ASSOCIATE_RIGHT };
enum { LEX_NUMBER, LEX_OPERATOR, LEX_END };

struct eval;
typedef struct eval eval_t;
typedef unsigned bit_t;

typedef struct operations {
	char *name;
	number_t (*eval) (eval_t *e, number_t a1, number_t a2);
	int precedence, unary, assocativity;
} operations_t;

typedef struct {
	char *name;
	number_t value;
} variable_t;

struct eval {
	const operations_t **ops, *lpar, *rpar, *negate, *minus;
	variable_t **vars;
	char id[MAX_ID];
	char error_string[MAX_ERROR];
	number_t number;
	const operations_t *op;
	number_t *numbers;
	size_t ops_count, ops_max;
	size_t numbers_count, numbers_max;
	size_t id_count;
	size_t vars_max;
	int error;
	int initialized;
};

void expr_delete(eval_t *e) {
	if (!e)
		return;
	free(e->ops);
	free(e->numbers);
	for (size_t i = 0; i < e->vars_max; i++) {
		free(e->vars[i]->name);
		free(e->vars[i]);
	}
	free(e->vars);
	free(e);
}

static const operations_t *op_get(const char *op);

eval_t *expr_new(size_t max) {
	max = max ? max : 64;
	eval_t *e = calloc(sizeof(*e), 1);
	if (!e)
		goto fail;
	e->ops     = calloc(sizeof(**e->ops), max);
	e->numbers = calloc(sizeof(*(e->numbers)), max);
	if (!(e->ops) || !(e->numbers))
		goto fail;
	e->ops_max     = max;
	e->numbers_max = max;
	e->lpar   = op_get("(");
	e->rpar   = op_get(")");
	e->negate = op_get("negate");
	e->minus  = op_get("-");
	assert(e->lpar && e->rpar && e->negate && e->minus);
	e->initialized = 1;
	return e;
fail:
	expr_delete(e);
	return NULL;
}

static int error(eval_t *e, const char *fmt, ...) {
	assert(e);
	assert(fmt);
	if (e->error)
		return 0;
	va_list ap;
	va_start(ap, fmt);
	const int r = vsnprintf(e->error_string, sizeof (e->error_string), fmt, ap);
	va_end(ap);
	e->error = -1;
	return r;
}

static number_t numberify(const char *s) {
	if (USE_FLOAT)
		return atof(s);
	return atol(s);
}

static inline number_t op_negate (eval_t *e, number_t a, number_t b) { assert(e); UNUSED(b); return -a; }
static inline number_t op_invert (eval_t *e, number_t a, number_t b) { assert(e); UNUSED(b); return ~(bit_t)a; }
static inline number_t op_not    (eval_t *e, number_t a, number_t b) { assert(e); UNUSED(b); return !a; }
static inline number_t op_mul    (eval_t *e, number_t a, number_t b) { assert(e); return a * b; }
static inline number_t op_add    (eval_t *e, number_t a, number_t b) { assert(e); return a + b; }
static inline number_t op_sub    (eval_t *e, number_t a, number_t b) { assert(e); return a - b; }
static inline number_t op_and    (eval_t *e, number_t a, number_t b) { assert(e); return (bit_t)a & (bit_t)b; }
static inline number_t op_or     (eval_t *e, number_t a, number_t b) { assert(e); return (bit_t)a | (bit_t)b; }
static inline number_t op_xor    (eval_t *e, number_t a, number_t b) { assert(e); return (bit_t)a ^ (bit_t)b; }
static inline number_t op_lshift (eval_t *e, number_t a, number_t b) { assert(e); return (bit_t)a << (bit_t)b; }
static inline number_t op_rshift (eval_t *e, number_t a, number_t b) { assert(e); return (bit_t)a >> (bit_t)b; }
static inline number_t op_less   (eval_t *e, number_t a, number_t b) { assert(e); return a < b; }
static inline number_t op_more   (eval_t *e, number_t a, number_t b) { assert(e); return a > b; }
static inline number_t op_eqless (eval_t *e, number_t a, number_t b) { assert(e); return a <= b; }
static inline number_t op_eqmore (eval_t *e, number_t a, number_t b) { assert(e); return a >= b; }
static inline number_t op_equal  (eval_t *e, number_t a, number_t b) { assert(e); return a == b; }
static inline number_t op_unequal(eval_t *e, number_t a, number_t b) { assert(e); return a != b; }

static inline number_t op_sin    (eval_t *e, number_t a, number_t b) { assert(e); UNUSED(b); return sin(a); }
static inline number_t op_cos    (eval_t *e, number_t a, number_t b) { assert(e); UNUSED(b); return cos(a); }
static inline number_t op_tan    (eval_t *e, number_t a, number_t b) { assert(e); UNUSED(b); return tan(a); }
static inline number_t op_asin   (eval_t *e, number_t a, number_t b) { assert(e); UNUSED(b); return asin(a); }
static inline number_t op_acos   (eval_t *e, number_t a, number_t b) { assert(e); UNUSED(b); return acos(a); }
static inline number_t op_atan   (eval_t *e, number_t a, number_t b) { assert(e); UNUSED(b); return atan(a); }
static inline number_t op_log    (eval_t *e, number_t a, number_t b) { assert(e); UNUSED(b); return log(a); }
static inline number_t op_exp    (eval_t *e, number_t a, number_t b) { assert(e); UNUSED(b); return exp(a); }

static inline number_t op_pow(eval_t *e, number_t b, number_t a) {
	assert(e);
	if (USE_FLOAT)
		return pow(a, b);
	number_t r = 1;
	for (;;) {
		if ((bit_t)a & (bit_t)1u)
			r *= b;
		a = a / 2;
		if (!a)
			break;
		b *= b;
	}
	return r;
}

static number_t op_div(eval_t *e, number_t a, number_t b) {
	assert(e);
	if (!b) {
		error(e, "division by zero");
		return 0; /* error handled later */
	}
	if (!USE_FLOAT) {
		BUILD_BUG_ON(!USE_FLOAT && sizeof(number_t) != sizeof(int));
		if (a == INT_MIN && b == -1) {
			error(e, "overflow in division");
			return 0;
		}
	}
	return a / b;
}

static number_t op_mod(eval_t *e, number_t a, number_t b) {
	assert(e);
	if (!b) {
		error(e, "division by zero");
		return 0; /* error handled later */
	}
	if (USE_FLOAT)
		return fmod(a, b);
	if (!USE_FLOAT) {
		BUILD_BUG_ON(!USE_FLOAT && sizeof(number_t) != sizeof(int));
		if (a == INT_MIN && b == -1) {
			error(e, "overflow in division");
			return 0;
		}
	}
	return (bit_t)a % (bit_t)b;
}

static inline number_t op_rotl(eval_t *e, number_t a, number_t b) {
	assert(e);
	bit_t value = a, shift = b;
	BUILD_BUG_ON(!USE_FLOAT && (sizeof(number_t) != sizeof(bit_t)));
	shift &= (sizeof(value) * CHAR_BIT) - 1u;
	if (!shift)
		return value;
	return (value << shift) | (value >> ((sizeof(value) * CHAR_BIT) - shift));
}

static inline number_t op_rotr(eval_t *e, number_t a, number_t b) {
	assert(e);
	bit_t value = a, shift = b;
	BUILD_BUG_ON(!USE_FLOAT && (sizeof(number_t) != sizeof(bit_t)));
	shift &= (sizeof(value) * CHAR_BIT) - 1u;
	if (!shift)
		return value;
	return (value >> shift) | (value << ((sizeof(value) * CHAR_BIT) - shift));
}

static const operations_t *op_get(const char *op) {
	assert(op);
	static const operations_t ops[] = { // Binary Search Table
	#if USE_FLOAT == 0
		{  "!",       op_not,      5,  1,  ASSOCIATE_RIGHT,  },
		{  "!=",      op_unequal,  2,  0,  ASSOCIATE_LEFT,   },
		{  "%",       op_mod,      3,  0,  ASSOCIATE_LEFT,   },
		{  "&",       op_and,      2,  0,  ASSOCIATE_LEFT,   },
		{  "(",       NULL,        0,  0,  ASSOCIATE_NONE,   },
		{  ")",       NULL,        0,  0,  ASSOCIATE_NONE,   },
		{  "*",       op_mul,      3,  0,  ASSOCIATE_LEFT,   },
		{  "+",       op_add,      2,  0,  ASSOCIATE_LEFT,   },
		{  "-",       op_sub,      2,  0,  ASSOCIATE_LEFT,   },
		{  "/",       op_div,      3,  0,  ASSOCIATE_LEFT,   },
		{  "<",       op_less,     2,  0,  ASSOCIATE_LEFT,   },
		{  "<<",      op_lshift,   4,  0,  ASSOCIATE_RIGHT,  },
		{  "<=",      op_eqless,   2,  0,  ASSOCIATE_LEFT,   },
		{  "==",      op_equal,    2,  0,  ASSOCIATE_LEFT,   },
		{  ">",       op_more,     2,  0,  ASSOCIATE_LEFT,   },
		{  ">=",      op_eqmore,   2,  0,  ASSOCIATE_LEFT,   },
		{  ">>",      op_rshift,   4,  0,  ASSOCIATE_RIGHT,  },
		{  "^",       op_xor,      2,  0,  ASSOCIATE_LEFT,   },
		{  "negate",  op_negate,   5,  1,  ASSOCIATE_RIGHT,  },
		{  "pow",     op_pow,      4,  0,  ASSOCIATE_RIGHT,  },
		{  "rotl",    op_rotl,     4,  0,  ASSOCIATE_RIGHT,  },
		{  "rotr",    op_rotr,     4,  0,  ASSOCIATE_RIGHT,  },
		{  "|",       op_or,       2,  0,  ASSOCIATE_LEFT,   },
		{  "~",       op_invert,   5,  1,  ASSOCIATE_RIGHT,  },
	#else
		{  "!",       op_not,      5,  1,  ASSOCIATE_RIGHT,  },
		{  "!=",      op_unequal,  2,  0,  ASSOCIATE_LEFT,   },
		{  "%",       op_mod,      3,  0,  ASSOCIATE_LEFT,   },
		{  "(",       NULL,        0,  0,  ASSOCIATE_NONE,   },
		{  ")",       NULL,        0,  0,  ASSOCIATE_NONE,   },
		{  "*",       op_mul,      3,  0,  ASSOCIATE_LEFT,   },
		{  "+",       op_add,      2,  0,  ASSOCIATE_LEFT,   },
		{  "-",       op_sub,      2,  0,  ASSOCIATE_LEFT,   },
		{  "/",       op_div,      3,  0,  ASSOCIATE_LEFT,   },
		{  "<",       op_less,     2,  0,  ASSOCIATE_LEFT,   },
		{  "<=",      op_eqless,   2,  0,  ASSOCIATE_LEFT,   },
		{  "==",      op_equal,    2,  0,  ASSOCIATE_LEFT,   },
		{  ">",       op_more,     2,  0,  ASSOCIATE_LEFT,   },
		{  ">=",      op_eqmore,   2,  0,  ASSOCIATE_LEFT,   },
		{  "acos",    op_acos,     5,  1,  ASSOCIATE_RIGHT,  },
		{  "asin",    op_asin,     5,  1,  ASSOCIATE_RIGHT,  },
		{  "atan",    op_atan,     5,  1,  ASSOCIATE_RIGHT,  },
		{  "cos",     op_cos,      5,  1,  ASSOCIATE_RIGHT,  },
		{  "exp",     op_exp,      5,  1,  ASSOCIATE_RIGHT,  },
		{  "log",     op_log,      5,  1,  ASSOCIATE_RIGHT,  },
		{  "negate",  op_negate,   5,  1,  ASSOCIATE_RIGHT,  },
		{  "pow",     op_pow,      4,  0,  ASSOCIATE_RIGHT,  },
		{  "sin",     op_sin,      5,  1,  ASSOCIATE_RIGHT,  },
		{  "tan",     op_tan,      5,  1,  ASSOCIATE_RIGHT,  },
	#endif
	};
	const size_t length = (sizeof ops / sizeof ops[0]);
	size_t l = 0, r = length - 1;
	while (l <= r) { // Iterative Binary Search
		size_t m = l + ((r - l)/2u);
		assert (m < length);
		const int comp = strcmp(ops[m].name, op);
		if (comp == 0)
			return &ops[m];
		if (comp < 0)
			l = m + 1;
		else
			r = m - 1;
	}
	return NULL;
}

static int number_push(eval_t *e, number_t num) {
	assert(e);
	if (e->error)
		return -1;
	if (e->numbers_count > (e->numbers_max - 1)) {
		error(e, "number stack overflow");
		return -1;
	}
	e->numbers[e->numbers_count++] = num;
	return 0;
}

static number_t number_pop(eval_t *e) {
	assert(e);
	if (e->error)
		return -1;
	if (!(e->numbers_count)) {
		error(e, "number stack empty");
		return -1; /* error handled elsewhere */
	}
	return e->numbers[--(e->numbers_count)];
}

static int op_push(eval_t *e, const operations_t *op) {
	assert(e);
	assert(op);
	if (e->error)
		return -1;
	if (e->ops_count > (e->ops_max - 1)) {
		error(e, "operator stack overflow");
		return -1;
	}
	e->ops[e->ops_count++] = op;
	return 0;
}

static const operations_t *op_pop(eval_t *e) {
	assert(e);
	if (e->error)
		return NULL;
	if (!(e->ops_count)) {
		error(e, "operator stack empty");
		return NULL;
	}
	return e->ops[--(e->ops_count)];
}

static int op_eval(eval_t *e) {
	assert(e);
	const operations_t *pop = op_pop(e);
	if (!pop)
		return -1;
	const number_t a = number_pop(e);
	if (!(pop->eval)) {
		error(e, "syntax error");
		return -1;
	}
	if (pop->unary)
		return number_push(e, pop->eval(e, a, 0));
	const number_t b = number_pop(e);
	return number_push(e, pop->eval(e, b, a));
}

static int shunt(eval_t *e, const operations_t *op) {
	assert(e);
	assert(op);
	if (op == e->lpar) {
		return op_push(e, op);
	} else if (op == e->rpar) {
		while (e->ops_count && e->ops[e->ops_count - 1] != e->lpar)
			if (op_eval(e) < 0 || e->error)
				break;
		const operations_t *pop = op_pop(e);
		if (!pop || (pop != e->lpar)) {
			e->error = 0; /* clear error so following error is printed */
			error(e, "expected \"(\"");
			return -1;
		}
		return 0;
	} else if (op->assocativity == ASSOCIATE_RIGHT) {
		while (e->ops_count && op->precedence < e->ops[e->ops_count - 1]->precedence)
			if (op_eval(e) < 0 || e->error)
				break;
	} else {
		while (e->ops_count && op->precedence <= e->ops[e->ops_count - 1]->precedence)
			if (op_eval(e) < 0 || e->error)
				break;
	}
	return op_push(e, op);
}

static variable_t *variable_lookup(eval_t *e, const char *name) {
	assert(e);
	for (size_t i = 0; i < e->vars_max; i++) {
		variable_t *v = e->vars[i];
		if (!strcmp(v->name, name))
			return v;
	}
	return NULL;
}

static char *estrdup(const char *s) {
	assert(s);
	const size_t l = strlen(s) + 1;
	char *r = malloc(l);
	return memcpy(r, s, l);
}

static int variable_name_is_valid(const char *n) {
	assert(n);
	if (!isalpha(*n) && !(*n == '_'))
		return 0;
	for (n++; *n; n++)
		if (!isalnum(*n) && !(*n == '_'))
			return 0;
	return 1;
}

static variable_t *variable_add(eval_t *e, const char *name, number_t value) {
	assert(e);
	assert(name);
	variable_t *v = variable_lookup(e, name), **vs = e->vars;
	if (v) {
		v->value = value;
		return v;
	}
	if (!variable_name_is_valid(name))
		return NULL;
	char *s = estrdup(name);
	vs = realloc(e->vars, (e->vars_max + 1) * sizeof(*v));
	v = calloc(1, sizeof(*v));
	if (!vs || !v || !s)
		goto fail;
	v->name = s;
	v->value = value;
	vs[e->vars_max++] = v;
	e->vars = vs;
	return v;
fail:
	free(v);
	free(s);
	free(vs);
	return NULL;
}

static int lex(eval_t *e, const char **expr) {
	assert(e);
	assert(expr && *expr);
	int r = 0;
	const char *s = *expr;
	variable_t *v = NULL;
	e->id_count = 0;
	e->number = 0;
	e->op = NULL;
	memset(e->id, 0, sizeof (e->id));
	for (; *s && isspace(*s); s++)
		;
	if (!(*s))
		return LEX_END;
	if (isalpha(*s) || *s == '_') {
		for (; e->id_count < sizeof(e->id) && *s && (isalnum(*s) || *s == '_');)
			e->id[e->id_count++] = *s++;
		if ((v = variable_lookup(e, e->id))) {
			e->number = v->value;
			r = LEX_NUMBER;
		} else if ((e->op = op_get(e->id))) {
			r = LEX_OPERATOR;
		} else {
			r = -1;
		}
	} else {
		if (ispunct(*s)) {
			const operations_t *op1 = NULL, *op2 = NULL;
			int set = 0;
			e->id[e->id_count++] = *s++;
			op1 = op_get(e->id);
			if (*s && ispunct(*s)) {
				set = 1;
				e->id[e->id_count++] = *s++;
				op2 = op_get(e->id);
			}
			r = (op1 || op2) ? LEX_OPERATOR : -1;
			e->op = op2 ? op2 : op1;
			if (e->op == op1 && set) {
				s--;
				e->id_count--;
				e->id[1] = 0;
			}
		} else if (isdigit(*s)) {
			r = LEX_NUMBER;
			int dot = 0;
			for (; e->id_count < sizeof(e->id) && *s; s++) {
				const int ch = *s;
				if (!(isdigit(ch) || (USE_FLOAT && ch == '.' && !dot)))
					break;
				e->id[e->id_count++] = ch;
				if (ch == '.')
					dot = 1;
			}
			if (USE_FLOAT) {
				double d = 0;
				if (sscanf(e->id, "%lf", &d) != 1)
					r = -1;
				e->number = d;
			} else {
				e->number = numberify(e->id);
			}
		} else {
			r = -1;
		}
	}
	//printf("id(%d) %d => %s\n", (int)(s - *expr), r, e->id);
	*expr = s;
	return r;
}

static int expr_eval(eval_t *e, const char *expr) {
	assert(e);
	assert(expr);
	int firstop = 1;
	const operations_t *previous = NULL;
	if (e->initialized) {
		memset(e->error_string, 0, sizeof (e->error_string));
		e->error = 0;
		e->ops_count = 0;
		e->numbers_count = 0;
		e->initialized = 1;
	}
	for (int l = 0; l != LEX_END && !(e->error);) {
		switch ((l = lex(e, &expr))) {
		case LEX_NUMBER:   
			number_push(e, e->number); 
			previous = NULL; 
			firstop = 0;
			break;
		case LEX_OPERATOR: {
			const operations_t *op = e->op;
			if (firstop || (previous && previous != e->rpar)) {
				if (e->op == e->minus) {
					op = e->negate;
				} else if (e->op->unary) {
					// Do nothing
				} else if (e->op != e->lpar) {
					assert(e->op);
					error(e, "invalid use of \"%s\"", e->op->name);
					goto end;
				}
			}
			shunt(e, op); 
			previous = op; 
			firstop = 0;
			break;
		}
		case LEX_END: break;
		default:
			error(e, "invalid symbol: %s", e->id);
			l = LEX_END;
		}
	}
	while (e->ops_count)
		if (op_eval(e) < 0 || e->error)
			break;
	if (e->numbers_count != 1) {
		error(e, "invalid expression: %d", e->numbers_count);
		return -1;
	}
	implies(e->error == 0, e->numbers_count == 1);
end:
	return e->error == 0 ? 0 : -1;
}

static inline int tests(FILE *out) {
	assert(out);
	int report = 0;
	static const struct test {
		int r;
		number_t result;
		const char *expr;
	} tests[] = { // NB. Variables defined later.
		{  -1,    0,   ""            },
		{  -1,    0,   "("           },
		{  -1,    0,   ")"           },
		{  -1,    0,   "2**3"        },
		{   0,    0,   "0"           },
		{   0,    2,   "1+1"         },
		{   0,   -1,   "-1"          },
		{   0,    1,   "--1"         },
		{   0,   14,   "2+(3*4)"     },
		{   0,   23,   "a+(b*5)"     },
		{  -1,   14,   "(2+(3* 4)"   },
		{  -1,   14,   "2+(3*4)("    },
		{   0,   14,   "2+3*4"       },
		{   0,    0,   "  2==3 "     },
		{   0,    1,   "2 ==2"       },
		{   0,    1,   "2== (1+1)"   },
		{   0,    8,   "2 pow 3"     },
		{  -1,    0,   "2pow3"       },
		{   0,   20,   "(2+3)*4"     },
		{   0,   -4,   "(2+(-3))*4"  },
		{  -1,    0,   "1/0"         },
		{  -1,    0,   "1%0"         },
		{   0,   50,   "100/2"       },
		{   0,    2,   "1--1",       },
		{   0,    0,   "1---1",      },
	};

	fputs("Running Built In Self Tests:\n", out);
	const size_t length = sizeof (tests) / sizeof (tests[0]);
	for (size_t i = 0; i < length; i++) {
		eval_t *e = expr_new(64);
		const struct test *test = &tests[i];
		if (!e) {
			fprintf(out, "test failed (unable to allocate)\n");
			report = -1;
			goto end;
		}

		variable_t *v1 = variable_add(e, "a",  3);
		variable_t *v2 = variable_add(e, "b",  4);
		variable_t *v3 = variable_add(e, "c", -5);
		if (!v1 || !v2 || !v3) {
			fprintf(out, "test failed (unable to assign variable)\n");
			report = -1;
			goto end;
		}

		const int r = expr_eval(e, test->expr);
		const number_t tos = e->numbers[0];
		const int pass = (r == test->r) && (r != 0 || tos == test->result);
		fprintf(out, "%s: r(%2d), eval(\"%s\") = %lg \n",
				pass ? "   ok" : " FAIL", r, test->expr, (double)tos);
		if (!pass) {
			report = -1;
			fprintf(out, "\tExpected: r(%2d), %lg\n",
				test->r, (double)(test->result));
		}
		expr_delete(e);
	}
end:
	fprintf(out, "Tests Complete: %s\n", report == 0 ? "pass" : "FAIL");
	return report;
}

static int usage(FILE *out, const char *arg0) {
	assert(out);
	assert(arg0);
	return fprintf(out, "usage: %s expr\n", arg0);
}

int main(int argc, char *argv[]) {
	int r = 0;
	eval_t *e = expr_new(0);

	if (!e) {
		fprintf(stderr, "allocate failed\n");
		r = 1;
		goto end;
	}

	if (argc == 1) {
		usage(stderr, argv[0]);
		return tests(stderr);
	}

	if (argc < 2) {
		fprintf(stderr, "usage: %s expr\n", argv[0]);
		r = 1;
		goto end;
	}

	if (expr_eval(e, argv[1]) == 0) {
		printf(USE_FLOAT ? "%g\n" : "%d\n", e->numbers[0]);
		r = 0;
		goto end;
	} else {
		fprintf(stderr, "error: %s\n", e->error_string);
	}
end:
	expr_delete(e);
	return r;
}

