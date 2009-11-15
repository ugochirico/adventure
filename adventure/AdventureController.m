#import "AdventureController.h"
#include <SWI-Prolog.h>

// Yeah, side-effects!
// The communication between the SWI-Prolog thread and the Cocoa app is 
// controlled by a few global Variables, and a global lock that controls
// the access to these variables
extern int the_argc;
extern char **the_argv;
static id theController = nil;
static struct { int r; int w; } thePipe;

void abort_interpreter() {
  PL_cleanup(0);
 // ??
}

foreign_t pl_getch(term_t a0)
{
  unichar c;
  term_t t1 = PL_new_term_ref();
  read(thePipe.r, &c, sizeof(unichar));
  PL_put_integer(t1, c);
  PL_unify(a0, t1);
  PL_succeed;
}

foreign_t pl_write_xy(term_t a0, term_t a1, term_t a2)
{
  char *s;
  int x, y;//, old_x, old_y, new_x, new_y;
  if (PL_get_atom_chars(a0, &s) && 
      PL_get_integer(a1, &x) && 
      PL_get_integer(a2, &y)) {
    // if x, y < 0 use default cursor else draw at x,y and restore cursor pos
    //getyx(win, old_y, old_x);
    //move(y>=0?y:old_y, x>=0?x:old_x);
    //printw("%s", s);
    //getyx(win, new_y, new_x);
    //move(y>=0?old_y:new_y, x>=0?old_x:new_x)
	[theController sayText :[NSString stringWithUTF8String :s]];
    PL_succeed;
  } else {
    //printw("ERROR!");
    exit(1);
    PL_fail;
  }
}

foreign_t pl_bold()   { PL_succeed; }
foreign_t pl_italic() { PL_succeed; }
foreign_t pl_roman()  { PL_succeed; }

@implementation AdventureController

- (id)init
{
	theController = [super init];
	NSAssert(pipe(&thePipe) == 0, @"Could not create pipe!");
	lastPos = 0;
	[NSThread detachNewThreadSelector:@selector(prologEngine:) toTarget:self withObject:nil];
	return theController;
}

- (IBAction)enterPressed:(id)sender
{
    //[textView setString :[[tokenField objectValue] componentsJoinedByString :@" "]];
	// Den puffer auffuellen!
	[tokenField setObjectValue :nil];
}

-(void) sayText :(NSString*) text
{
    [textView setString :text];
}

- (NSArray *)tokenField:(NSTokenField *)tokenField 
	completionsForSubstring:(NSString *)substring 
	indexOfToken:(int)tokenIndex 
	indexOfSelectedItem:(int *)selectedIndex
{
	while (lastPos > [substring length]) { // remove characters
		write(thePipe.w, (unichar)'\b', sizeof(unichar));
		--lastPos;
	}

	while (lastPos < [substring length]) { // push characters
		write(thePipe.w, [substring characterAtIndex:lastPos], sizeof(unichar));
		++lastPos;
	}
	NSAssert(lastPos == [substring length], nil);
	return nil; //[NSArray arrayWithObjects:@"1", @"2", nil];
}

-(void) prologEngine :(id)anObject
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  char *av[10];
  int ac = 0;

  av[ac++] = the_argv[0];
  av[ac++] = strdup("-q");
  //av[ac++] = strdup("-O");
  // Sizes of "0" mean the largest possible limits.
  /* av[ac++] = strdup("-L0");  // Local stack */
  /* av[ac++] = strdup("-G0");  // Global stack */
  /* av[ac++] = strdup("-A0");  // Argument stack */
  /* av[ac++] = strdup("-T0");  // Trail stack */
  av[ac++] = strdup("-nosignals");
  atexit(abort_interpreter);
  av[ac]   = NULL;
  
  if ( !PL_initialise(ac, av) )
    PL_halt(1);
  
  // Register foreign predicates with the interpreter
  PL_register_foreign("getch", 1, pl_getch, 0);
  PL_register_foreign("write_xy", 3, pl_write_xy, 0);
  PL_register_foreign("bold", 0, pl_bold, 0);
  PL_register_foreign("italic", 0, pl_italic, 0);
  PL_register_foreign("roman", 0, pl_roman, 0);

  // Load our own modules
  term_t t1 = PL_new_term_ref();
  const char* path = [[NSString stringWithFormat:@"'%@/Contents/Resources/%@'", 
	[[NSBundle mainBundle] bundlePath], @"advcore2"] UTF8String];
  PL_chars_to_term(path, t1);
  PL_call_predicate(NULL, PL_Q_NORMAL, PL_predicate("consult", 1, ""), t1);

  // Run the module
  term_t goal = PL_new_term_ref();
  PL_chars_to_term("main", goal);
  PL_call(goal, PL_new_module(PL_new_atom("advcore2")));
  
  PL_halt(/*PL_toplevel() ?*/ 0/* : 1 */);
  [pool release];
}

@end
