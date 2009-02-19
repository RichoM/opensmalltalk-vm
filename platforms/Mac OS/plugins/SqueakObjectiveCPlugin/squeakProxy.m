//
//  squeakProxy.m
//  SqueakObjectiveC
//
//  Created by John M McIntosh on 01/02/09.
//  Copyright 2009 Corporate Smalltalk Consulting Ltd. All rights reserved.

/* 
 Some code from 
 http://www.squeaksource.com/ObjectiveCBridge.html
 developers and contributors 
 Creator:	Alain Fischer
 Admin:	Avi Bryant, Alain Fischer
 Developer:	Todd Blanchard
 
 MIT License
 Permission is hereby granted, free of charge, to any person
 obtaining a copy of this software and associated documentation
 files (the "Software"), to deal in the Software without
 restriction, including without limitation the rights to use,
 copy, modify, merge, publish, distribute, sublicense, and/or sell 
 copies of the Software, and to permit persons to whom the
 Software is furnished to do so, subject to the following
 conditions:
 
 The above copyright notice and this permission notice shall be
 included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 OTHER DEALINGS IN THE SOFTWARE.
 
 The end-user documentation included with the redistribution, if any, must include the following acknowledgment: 
 "This product includes software developed by Corporate Smalltalk Consulting Ltd (http://www.smalltalkconsulting.com) 
 and its contributors", in the same place and form as other third-party acknowledgments. 
 Alternately, this acknowledgment may appear in the software itself, in the same form and location as other 
 such third-party acknowledgments.
 */
//

#import "squeakProxy.h"


@implementation SqueakProxy

@synthesize sem;
@synthesize invocation;
@synthesize lock;
@synthesize sigs;
@synthesize protocol;
@synthesize target;

- (id) initWithSemaphore: (sqInt) squeakSem protocolNSString: (NSString *) nameString target: aTarget
{
	sem = squeakSem;
	if (nameString)
		protocol = objc_getProtocol([nameString UTF8String]);
	else
		protocol = nil;
	
	if (aTarget) {
		[self setTarget: aTarget];
	} else {
		NSObject *dummy = [[NSObject alloc] init];
		[self setTarget: dummy];
		[dummy release];
	}
	
	lock = [[NSConditionLock alloc] initWithCondition: 0];
	sigs = [[NSMutableSet alloc] init];
	
	return self;
}


- (void) forwardInvocation: (NSInvocation*) anInvocation
{
	NSDate *timeout;
	//	NSLog(@"forwardInvocation: %@", anInvocation);
	//	NSLog(@"currentThread: %@", [NSThread currentThread]);
	
	if (![sigs containsObject: NSStringFromSelector([anInvocation selector])]) {
		[target forwardInvocation: anInvocation];
		return;
	}
	
	if([lock lockWhenCondition: 0 beforeDate: (timeout = [[NSDate alloc] initWithTimeIntervalSinceNow: 3])])
	{ 
		// NSLog(@"inside lock 0");
		[lock unlockWithCondition: 1];
		[timeout release];
		invocation = [anInvocation retain];
		
		// NSLog(@"signalling squeak");
		interpreterProxy->signalSemaphoreWithIndex(sem);
		if([lock lockWhenCondition: 2 beforeDate: (timeout = [[NSDate alloc] initWithTimeIntervalSinceNow: 4])])
		{
			// NSLog(@"inside lock 2");
			[timeout release];
			[invocation release];
			invocation = nil;
			[lock unlockWithCondition: 0];
		}
		else
		{
			// NSLog(@"failed lock 2");
			[timeout release];
			[invocation release];
			invocation = nil;
			[lock unlockWithCondition: 0];
		}
		//NSLog(@"returning");
	}
	else
	{
		[timeout release];
		//NSLog(@"failed lock 0");
	}
}

- (NSMethodSignature *) methodSignatureForSelector: (SEL) selector
{
	NSMethodSignature* sig;
	sig = [target methodSignatureForSelector: selector];
	if (sig)
		return sig;
	
	
	sig = [super methodSignatureForSelector: selector];
	if(sig) 
		return sig;
	
	NSString *selectorString = NSStringFromSelector (selector);
	
	if ([sigs containsObject: selectorString]) {
		
		if (protocol) {
			struct objc_method_description methodDescription;
			methodDescription = protocol_getMethodDescription(protocol, selector, YES, YES);
			if(methodDescription.name == NULL) {
				methodDescription = protocol_getMethodDescription(protocol, selector, NO, YES);
			}
			
			if(methodDescription.name != NULL) {
				NSMethodSignature *foo = [NSMethodSignature signatureWithObjCTypes:methodDescription.types];
				return foo;
			}
		}
		
		/* Fake the signature types by sub in object pointers */ 
		
		int colonCount = [[selectorString componentsSeparatedByString: @":"] count] - 1;
		NSMutableString *signatureString = [NSMutableString stringWithString: @"@@:"];
		int i;
		
		for (i = 0; i < colonCount; i++) {
			[signatureString appendString: @"@"];
		}
		
		NSMethodSignature *result = [NSMethodSignature signatureWithObjCTypes: [signatureString UTF8String]];
		return result;
		
	}
	return nil;
}	

- (BOOL) respondsToSelector: (SEL) selector
{
	if([super respondsToSelector: selector]) 
		return true;
	
	if ([target respondsToSelector: selector]) 
		return true;
	
	NSString *which = NSStringFromSelector(selector);
	
	if ([sigs containsObject: which]) 
		return true;
	
	return false;
}

- (void) setReturnValue: (char*) pointer {
	[invocation setReturnValue: pointer];
}

- (void) dealloc
{
	[lock release];
	[sigs release];
	[target release];
	[super dealloc];
}

@end
