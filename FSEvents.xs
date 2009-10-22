#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <pthread.h>

// A single event
struct event {
    struct event *next;
    
    FSEventStreamEventId id;
    FSEventStreamEventFlags flags;
    char *path;
};

// Queue of events that need to be returned
struct queue {
    struct event *head;
    struct event *tail;
};

// The Mac::FSEvents object
typedef struct {
    char *path;
    FSEventStreamRef stream;
    CFAbsoluteTime latency;
    FSEventStreamEventId since;
    int respipe[2]; // pipe for thread to signal Perl for new event
    int reqpipe[2]; // pipe for Perl to signal thread to shutdown
    pthread_t tid;
    pthread_mutex_t mutex;
    struct queue *queue;
} FSEvents;

void
_init (FSEvents *self) {
    Zero(self, 1, FSEvents);
    
    self->respipe[0] = -1;
    self->respipe[1] = -1;
    self->reqpipe[0] = -1;
    self->reqpipe[1] = -1;
    self->latency    = 2.0;
    self->since      = kFSEventStreamEventIdSinceNow;
    
    self->queue       = calloc(1, sizeof(struct queue));
    self->queue->head = NULL;
    self->queue->tail = NULL;
}

void
_cleanup(FSEvents *self) {
    FSEventStreamStop(self->stream);
    FSEventStreamInvalidate(self->stream);
    FSEventStreamRelease(self->stream);
    
    self->stream = NULL;
    
    // Reset respipe
    close( self->respipe[0] );
    close( self->respipe[1] );
    self->respipe[0] = -1;
    self->respipe[1] = -1;
    
    // Reset reqpipe
    close( self->reqpipe[0] );
    close( self->reqpipe[1] );
    self->reqpipe[0] = -1;
    self->reqpipe[1] = -1;
    
    // Stop the loop and exit the thread
    CFRunLoopStop( CFRunLoopGetCurrent() );
}

void
_signal_stop(
    CFFileDescriptorRef fdref,
    CFOptionFlags callBackTypes,
    void *info
) {
    char buf[4];
    FSEvents *self = (FSEvents *)info;
    int fd = CFFileDescriptorGetNativeDescriptor(fdref);
    
    // Read dummy byte
    while ( read(fd, buf, 4) == 4 );
    
    CFFileDescriptorInvalidate(fdref);
    CFRelease(fdref);
    
    _cleanup(self);
}

void
streamEvent(
    ConstFSEventStreamRef streamRef,
    void *info,
    size_t numEvents,
    void *eventPaths,
    const FSEventStreamEventFlags eventFlags[],
    const FSEventStreamEventId eventIds[]
) {
    int i, n;
    char **paths = eventPaths;
    
    FSEvents *self = (FSEvents *)info;
    
    pthread_mutex_lock(&self->mutex);
    
    for (i=0; i<numEvents; i++) {
        struct event *e = calloc(1, sizeof(struct event));
        
        // Add event at tail of queue
        e->next = NULL;
        if ( self->queue->tail != NULL ) {
            self->queue->tail->next = e;
        }
        else {
            self->queue->head = e;
        }
        self->queue->tail = e;
        
        e->id    = eventIds[i];
        e->flags = eventFlags[i];
        e->path  = calloc(1, strlen(paths[i]) + 1);
        strcpy( e->path, (const char *)paths[i] );
        
        //fprintf( stderr, "Change %llu in %s, flags %lu\n", eventIds[i], paths[i], eventFlags[i] );
    }
    
    // Signal the filehandle with a dummy byte
    write(self->respipe[1], (const void *)&self->respipe, 1);
    
    pthread_mutex_unlock(&self->mutex);
}

void *
_watch_thread(void *arg) {
    FSEvents *self = (FSEvents *)arg;
    
    CFStringRef macpath = CFStringCreateWithCString(
        NULL,
        self->path,
        kCFStringEncodingUTF8
    );
    
    CFArrayRef pathsToWatch = CFArrayCreate(
        NULL,
        (const void **)&macpath,
        1,
        NULL
    );
    
    void *callbackInfo = (void *)self;
    
    FSEventStreamRef stream;
    
    CFRunLoopRef mainLoop = CFRunLoopGetCurrent();
    
    FSEventStreamContext context = { 0, (void *)self, NULL, NULL, NULL };
    
    CFFileDescriptorContext fdcontext = { 0, (void *)self, NULL, NULL, NULL };
    
    // This basically sets up a select() on the file descriptor we watch for stop events
    CFFileDescriptorRef fdref = CFFileDescriptorCreate(
        NULL,
        self->reqpipe[0],
        true,
        _signal_stop,
        &fdcontext
    );
    
    CFRunLoopSourceRef source;
    
    CFFileDescriptorEnableCallBacks( fdref, kCFFileDescriptorReadCallBack );
    source = CFFileDescriptorCreateRunLoopSource( NULL, fdref, 0 );    
    CFRunLoopAddSource( mainLoop, source, kCFRunLoopDefaultMode );
    CFRelease(source);
    
    stream = FSEventStreamCreate(
        NULL,
        streamEvent,
        &context,
        pathsToWatch,
        self->since,
        self->latency,
        kFSEventStreamCreateFlagNone
    );
    
    FSEventStreamScheduleWithRunLoop(
        stream,
        mainLoop,
        kCFRunLoopDefaultMode
    );
    
    FSEventStreamStart(stream);
    
    self->stream = stream;
    
    CFRunLoopRun();
}

MODULE = Mac::FSEvents      PACKAGE = Mac::FSEvents

void
new (char *klass, HV *args)
PPCODE:
{
    SV *pv = NEWSV(0, sizeof(FSEvents));
    SV **svp;
    
    FSEvents *self = (FSEvents *)SvPVX(pv);
    
    SvPOK_only(pv);

    _init(self);
    
    if ((svp = hv_fetch(args, "latency", 7, FALSE))) {
        self->latency = (CFAbsoluteTime)SvNV(*svp);
    }
    
    if ((svp = hv_fetch(args, "since", 5, FALSE))) {
        self->since = (FSEventStreamEventId)SvIV(*svp);
    }
    
    if ((svp = hv_fetch(args, "path", 4, FALSE))) {
        self->path = calloc(1, sv_len(*svp) + 1);
        strcpy( self->path, SvPVX(*svp) );
    }
    
    if ( !self->path ) {
        croak( "Error: path argument to new() must be supplied" );
    }
    
    XPUSHs( sv_2mortal( sv_bless(
        newRV_noinc(pv),
        gv_stashpv(klass, 1)
    ) ) );
}

void
_DESTROY(FSEvents *self)
CODE:
{
    if ( !self ) {
        return;
    }
    
    if ( !self->tid ) {
        // Work around a weird bug under Snow Leopard where we get a second
        // DESTROY on an object that was never created, and has no thread?!
        return;
    }        
    
    if ( self->path ) {
        free( self->path );
        self->path = NULL;
    }
    
    if ( self->queue ) {
        free( self->queue );
        self->queue = NULL;
    }
}

FILE *
watch(FSEvents *self)
CODE:
{
    int err;
    FILE *fh;
    
    if (self->respipe[0] > 0) {
        fprintf( stderr, "Error: already watching, please call stop() first\n" );
        XSRETURN_UNDEF;
    }
    
    if ( pipe( self->respipe ) ) {
        croak("unable to initialize result pipe");
    }
    
    if ( pipe( self->reqpipe ) ) {
        croak("unable to initialize request pipe");
    }
    
    if ( pthread_mutex_init(&self->mutex, NULL) != 0 ) {
        croak( "Error: unable to initialize mutex" );
    }
    
    err = pthread_create( &self->tid, NULL, _watch_thread, (void *)self );
    if (err != 0) {
        croak( "Error: can't create thread: %s\n", err );
    }
    
    fh = fdopen( self->respipe[0], "r" );
    
    RETVAL = fh;
}
OUTPUT:
    RETVAL

void
stop(FSEvents *self)
CODE:
{    
    if ( !self ) {
        return;
    }
    
    if ( !self->stream ) {
        // We've already stopped
        return;
    }

    // Signal the thread with a dummy byte
    write(self->reqpipe[1], (const void *)&self->reqpipe, 1);
    
    // wait for it to stop
    pthread_join( self->tid, NULL );
}

void
read_events(FSEvents *self)
PPCODE:
{
    HV *event;
    char buf [4];
    struct event *e;
    
    if ( self->respipe[0] > 0 ) {
        // Read dummy bytes
        // This call will block until an event is ready if we're in polling mode
        while ( read(self->respipe[0], buf, 4) == 4 );
        
        pthread_mutex_lock(&self->mutex);
        
        // read queue into hash
        for (e = self->queue->head; e != NULL; e = e->next) {           
            event = newHV();
            
            hv_store( event, "id",    2, newSVuv(e->id), 0 );
            hv_store( event, "path",  4, newSVpv(e->path, 0), 0 );
            
            // Translate flags into friendly hash keys
            if ( e->flags > 0 ) {
                hv_store( event, "flags", 5, newSVuv(e->flags), 0 );
                
                if ( e->flags & kFSEventStreamEventFlagMustScanSubDirs ) {
                    hv_store( event, "must_scan_subdirs", 17, newSVuv(1), 0 );
                
                    if ( e->flags & kFSEventStreamEventFlagUserDropped ) {
                        hv_store( event, "user_dropped", 12, newSVuv(1), 0 );
                    }
                    else if ( e->flags & kFSEventStreamEventFlagKernelDropped ) {
                        hv_store( event, "kernel_dropped", 14, newSVuv(1), 0 );
                    }
                }
            
                if ( e->flags & kFSEventStreamEventFlagHistoryDone ) {
                    hv_store( event, "history_done", 12, newSVuv(1), 0 );
                }
            
                if ( e->flags & kFSEventStreamEventFlagMount ) {
                    hv_store( event, "mount", 5, newSVuv(1), 0 );
                }
                else if ( e->flags & kFSEventStreamEventFlagUnmount ) {
                    hv_store( event, "unmount", 7, newSVuv(1), 0 );
                }
            }
            
            XPUSHs( sv_2mortal( sv_bless(
                newRV_noinc( (SV *)event ),
                gv_stashpv("Mac::FSEvents::Event", 1)
            ) ) );
        }
        
        pthread_mutex_unlock(&self->mutex);
    }
    
    pthread_mutex_lock(&self->mutex);
    
    // free queue
    e = self->queue->head;
    while ( e != NULL ) {
        struct event *const next = e->next;
        free(e->path);
        free(e);
        e = next;
    }
    
    self->queue->head = NULL;
    self->queue->tail = NULL;
    
    pthread_mutex_unlock(&self->mutex);
}