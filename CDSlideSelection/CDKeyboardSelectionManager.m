/*
 Copyright (C) 2012 by Connor Duggan.
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 */

#import "CDKeyboardSelectionManager.h"

@interface CDKeyboardTouchInfo : NSObject

@property (assign) CGPoint movement;
@property (assign) NSTimeInterval time;

-(id)initWithTime:(NSTimeInterval)t;
-(id)initWithMovement:(CGPoint)m time:(NSTimeInterval)t;

@end

@implementation CDKeyboardTouchInfo

@synthesize movement, time;

-(id)initWithTime:(NSTimeInterval)t
{
    if((self = [super init]))
    {
        movement = CGPointZero;
        time = t;
    }
    return self;
}

-(id)initWithMovement:(CGPoint)m time:(NSTimeInterval)t
{
    if((self = [super init]))
    {
        movement = m;
        time = t;
    }
    return self;
}

@end

@interface CDKeyboardSelectionManager ()

-(NSSet*)keyboardTouchesFromEvent:(UIEvent*)event;
-(void)addTouchesInPhaseBegan:(NSSet*)touches atTime:(NSTimeInterval)time;
-(void)updateTouchesInPhaseMoved:(NSSet*)touches atTime:(NSTimeInterval)time;
-(void)updateActiveTextInput;
-(void)removeTouchesInPhaseEnded:(NSSet*)touches;

-(CGPoint)velocityForTouch:(UITouch*)touch;
-(CGPoint)averageVelocityForKeyboardTouches;
-(void)removeOldTouchInfoFromTouch:(UITouch*)touch;
-(CGPoint)movementForTouch:(UITouch*)touch;
-(float)selectionXChangeVelocityFromXTouchVelocity:(float)xTouchVelocity;
-(float)selectionYChangeVelocityFromYTouchVelocity:(float)yTouchVelocity;

@end


@implementation CDKeyboardSelectionManager

@synthesize textInputs, keyboardTouches, keyboardTouchInfo, activeTextInput;

+ (id)sharedManager
{
    static dispatch_once_t pred = 0;
    __strong static id sharedManager = nil;
    dispatch_once(&pred, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

-(id)init
{
    if((self = [super init]))
    {
        self.textInputs = [NSMutableDictionary dictionaryWithCapacity:1];
        self.keyboardTouches = [NSMutableSet setWithCapacity:4];
        self.keyboardTouchInfo = [NSMutableDictionary dictionaryWithCapacity:4];
    }
    
    return self;
}

typedef enum
{
    kExtendingSelectionNone,
    kExtendingSelectionAtStart,
    kExtendingSelectionAtEnd,
} ExtendingSelect;

- (void)handleEvent:(UIEvent*)event
{
    static CGRect caretRectAfterXSelectionChange = (CGRect){0,0,0,0};
    static ExtendingSelect extendingSelection = kExtendingSelectionNone;
    
    NSSet * touchesForKeyboard = [self keyboardTouchesFromEvent:event];
    
    if(![touchesForKeyboard count]) return;
    
    NSTimeInterval currentTime = [NSDate timeIntervalSinceReferenceDate];
    
    [self addTouchesInPhaseBegan:touchesForKeyboard atTime:currentTime];
    [self updateTouchesInPhaseMoved:touchesForKeyboard atTime:currentTime];
    [self updateActiveTextInput];
    
    if(activeTextInput)
    {
        CGPoint averageTouchVelocity = [self averageVelocityForKeyboardTouches];
        movementAccumulator = CGPointMake(movementAccumulator.x + [self selectionXChangeVelocityFromXTouchVelocity:averageTouchVelocity.x], movementAccumulator.y + [self selectionYChangeVelocityFromYTouchVelocity:averageTouchVelocity.y]);
        
        UITextRange * selectedTextRange = [activeTextInput selectedTextRange];
        
        if(CGRectIsEmpty(caretRectAfterXSelectionChange))
        {
            caretRectAfterXSelectionChange = [activeTextInput caretRectForPosition:selectedTextRange.start];
        }
        
        int selectionStartIndex = [activeTextInput offsetFromPosition:activeTextInput.beginningOfDocument toPosition:selectedTextRange.start];
        int selectionEndIndex = [activeTextInput offsetFromPosition:activeTextInput.beginningOfDocument toPosition:selectedTextRange.end];

        int lengthFromSelectionStartToEndOfDocument = [activeTextInput offsetFromPosition:selectedTextRange.start toPosition:activeTextInput.endOfDocument];
        int lengthFromSelectionEndToEndOfDocument = [activeTextInput offsetFromPosition:selectedTextRange.end toPosition:activeTextInput.endOfDocument];

        
        if([self.keyboardTouches count] == 1)
        {
            if(movementAccumulator.x < -0.5f && selectionStartIndex > 0)
            {            
                int movementX = MAX((int)roundf(movementAccumulator.x), -selectionStartIndex);
                
                if(movementX)
                {
                    UITextPosition * offsetPosition = [activeTextInput positionFromPosition:selectedTextRange.start offset:movementX];
                    activeTextInput.selectedTextRange = [activeTextInput textRangeFromPosition:offsetPosition toPosition:offsetPosition];
                    
                    selectionHasChanged = YES;
                    movementAccumulator.y *= 0.5;
                    
                    movementAccumulator = CGPointMake(movementAccumulator.x - movementX, movementAccumulator.y);
                    
                    caretRectAfterXSelectionChange = [activeTextInput caretRectForPosition:offsetPosition];
                    
                }
            }
            else if(movementAccumulator.x > 0.5f && lengthFromSelectionStartToEndOfDocument)
            {
                int movementX = MIN((int)roundf(movementAccumulator.x), lengthFromSelectionStartToEndOfDocument);
                
                if(movementX)
                {
                    UITextPosition * offsetPosition = [activeTextInput positionFromPosition:selectedTextRange.start offset:movementX];
                    activeTextInput.selectedTextRange = [activeTextInput textRangeFromPosition:offsetPosition toPosition:offsetPosition];
                    selectionHasChanged = YES;
                    movementAccumulator.y *= 0.5;
                    
                    
                    movementAccumulator = CGPointMake(movementAccumulator.x - movementX, movementAccumulator.y);
                    
                    caretRectAfterXSelectionChange = [activeTextInput caretRectForPosition:offsetPosition];
                }
            }
            
            int movementY = (int)roundf(movementAccumulator.y);
            
            if(movementY != 0)
            {
                CGRect oldCaretRect = [activeTextInput caretRectForPosition:selectedTextRange.start];
                
                CGPoint point = CGPointMake(caretRectAfterXSelectionChange.origin.x, oldCaretRect.origin.y + oldCaretRect.size.height * movementY);
                
                UITextPosition * closest = [activeTextInput closestPositionToPoint:point];
                
                movementAccumulator.x *= 0.5;
                
                
                if([activeTextInput comparePosition:selectedTextRange.start toPosition:closest] != NSOrderedSame)
                {
                    activeTextInput.selectedTextRange = [activeTextInput textRangeFromPosition:closest toPosition:closest];
                    selectionHasChanged = YES;
                    
                    CGRect newCaretRect = [activeTextInput caretRectForPosition:closest];
                    
                    int actualMovementY = (newCaretRect.origin.y - oldCaretRect.origin.y) / oldCaretRect.size.height;
                    
                    movementAccumulator = CGPointMake(movementAccumulator.x, movementAccumulator.y - actualMovementY);
                }
            }
        }
        else if([self.keyboardTouches count] == 2)
        {
            if(movementAccumulator.x < -0.5f)
            {
                if(extendingSelection == kExtendingSelectionNone)
                {
                    extendingSelection = kExtendingSelectionAtStart;
                }
                
                if(extendingSelection == kExtendingSelectionAtStart)
                {
                    int movementX = MAX((int)roundf(movementAccumulator.x), -selectionStartIndex);
                    
                    if(movementX)
                    {
                        UITextPosition * offsetPosition = [activeTextInput positionFromPosition:selectedTextRange.start offset:movementX];
                        activeTextInput.selectedTextRange = [activeTextInput textRangeFromPosition:offsetPosition toPosition:selectedTextRange.end];
                        
                        selectionHasChanged = YES;
                        movementAccumulator.y *= 0.5;
                        
                        movementAccumulator = CGPointMake(movementAccumulator.x - movementX, movementAccumulator.y);
                        
                        caretRectAfterXSelectionChange = [activeTextInput caretRectForPosition:offsetPosition];

                    }
                }
                else
                {
                    int movementX = MAX((int)roundf(movementAccumulator.x), -selectionEndIndex);

                    UITextPosition * endPosition = [activeTextInput positionFromPosition:selectedTextRange.end offset:movementX];
                    
                    NSComparisonResult result = [activeTextInput comparePosition:endPosition toPosition:selectedTextRange.start];
                    
                    if(result == NSOrderedDescending)
                    {
                        activeTextInput.selectedTextRange = [activeTextInput textRangeFromPosition:selectedTextRange.start toPosition:endPosition];
                    }
                    else if(result == NSOrderedSame)
                    {
                        activeTextInput.selectedTextRange = [activeTextInput textRangeFromPosition:endPosition toPosition:endPosition];
                        extendingSelection = kExtendingSelectionNone;
                    }
                    else if(result == NSOrderedAscending)
                    {
                        activeTextInput.selectedTextRange = [activeTextInput textRangeFromPosition:endPosition toPosition:selectedTextRange.start];
                        extendingSelection = kExtendingSelectionAtStart;
                    }
                    
                    selectionHasChanged = YES;
                    movementAccumulator.y *= 0.5;
                    
                    movementAccumulator = CGPointMake(movementAccumulator.x - movementX, movementAccumulator.y);
                    
                }
            }
            else if(movementAccumulator.x > 0.5f)
            {
                if(extendingSelection == kExtendingSelectionNone)
                {
                    extendingSelection = kExtendingSelectionAtEnd;
                }
                
                if(extendingSelection == kExtendingSelectionAtEnd)
                {
                    int movementX = MIN((int)roundf(movementAccumulator.x), lengthFromSelectionEndToEndOfDocument);
                    
                    if(movementX)
                    {
                        UITextPosition * offsetPosition = [activeTextInput positionFromPosition:selectedTextRange.end offset:movementX];
                        activeTextInput.selectedTextRange = [activeTextInput textRangeFromPosition:selectedTextRange.start toPosition:offsetPosition];
                        
                        selectionHasChanged = YES;
                        movementAccumulator.y *= 0.5;
                        
                        movementAccumulator = CGPointMake(movementAccumulator.x - movementX, movementAccumulator.y);
                        
                        caretRectAfterXSelectionChange = [activeTextInput caretRectForPosition:offsetPosition];
                    }
                }
                else
                {
                    int movementX = MIN((int)roundf(movementAccumulator.x), lengthFromSelectionStartToEndOfDocument);
                    
                    UITextPosition * startPosition = [activeTextInput positionFromPosition:selectedTextRange.start offset:movementX];
                    
                    NSComparisonResult result = [activeTextInput comparePosition:startPosition toPosition:selectedTextRange.end];
                    
                    if(result == NSOrderedAscending)
                    {
                        activeTextInput.selectedTextRange = [activeTextInput textRangeFromPosition:startPosition toPosition:selectedTextRange.end];
                    }
                    else if(result == NSOrderedSame)
                    {
                        activeTextInput.selectedTextRange = [activeTextInput textRangeFromPosition:startPosition toPosition:startPosition];
                        extendingSelection = kExtendingSelectionNone;
                    }
                    else if(result == NSOrderedDescending)
                    {
                        activeTextInput.selectedTextRange = [activeTextInput textRangeFromPosition:selectedTextRange.end toPosition:startPosition];
                        extendingSelection = kExtendingSelectionAtEnd;
                    }
                    
                    selectionHasChanged = YES;
                    movementAccumulator.y *= 0.5;
                    
                    movementAccumulator = CGPointMake(movementAccumulator.x - movementX, movementAccumulator.y);
                }
            }
        
            int movementY = (int)roundf(movementAccumulator.y);
        
            if(movementY < -0.5f)
            {
                if(extendingSelection == kExtendingSelectionNone)
                {
                    extendingSelection = kExtendingSelectionAtStart;
                }
                
                CGRect oldCaretRect = [activeTextInput caretRectForPosition:extendingSelection == kExtendingSelectionAtStart? selectedTextRange.start : selectedTextRange.end];
                
                CGPoint point = CGPointMake(oldCaretRect.origin.x, oldCaretRect.origin.y + oldCaretRect.size.height * movementY);
            
                UITextPosition * closest = [activeTextInput closestPositionToPoint:point];
            
                movementAccumulator.x *= 0.5;
                
                NSComparisonResult result = [activeTextInput comparePosition:closest toPosition:selectedTextRange.start];
                
                if(result == NSOrderedAscending)
                {
                    activeTextInput.selectedTextRange = [activeTextInput textRangeFromPosition:closest toPosition:extendingSelection == kExtendingSelectionAtStart? selectedTextRange.end : selectedTextRange.start];
                    extendingSelection = kExtendingSelectionAtStart;
                }
                else if(result == NSOrderedSame)
                {
                    activeTextInput.selectedTextRange = [activeTextInput textRangeFromPosition:closest toPosition:closest];
                    extendingSelection = kExtendingSelectionNone;
                }
                else if(result == NSOrderedDescending)
                {
                    activeTextInput.selectedTextRange = [activeTextInput textRangeFromPosition:selectedTextRange.start toPosition:closest];
                    extendingSelection = kExtendingSelectionAtEnd;
                }
                
                selectionHasChanged = YES;
                
                CGRect newCaretRect = [activeTextInput caretRectForPosition:closest];
                
                int actualMovementY = (newCaretRect.origin.y - oldCaretRect.origin.y) / oldCaretRect.size.height;
                
                movementAccumulator = CGPointMake(movementAccumulator.x, movementAccumulator.y - actualMovementY);
                
            }
            else if(movementY > 0.5f)
            {
                if(extendingSelection == kExtendingSelectionNone)
                {
                    extendingSelection = kExtendingSelectionAtEnd;
                }
                
                CGRect oldCaretRect = [activeTextInput caretRectForPosition:extendingSelection == kExtendingSelectionAtStart? selectedTextRange.start : selectedTextRange.end];
                
                
                CGPoint point = CGPointMake(oldCaretRect.origin.x, oldCaretRect.origin.y + oldCaretRect.size.height * movementY);
                
                UITextPosition * closest = [activeTextInput closestPositionToPoint:point];
                
                movementAccumulator.x *= 0.5;
                
                NSComparisonResult result = [activeTextInput comparePosition:closest toPosition:selectedTextRange.end];
                
                if(result == NSOrderedDescending)
                {
                    activeTextInput.selectedTextRange = [activeTextInput textRangeFromPosition:extendingSelection == kExtendingSelectionAtStart? selectedTextRange.end : selectedTextRange.start toPosition:closest];
                    extendingSelection = kExtendingSelectionAtEnd;
                }
                else if(result == NSOrderedSame)
                {
                    activeTextInput.selectedTextRange = [activeTextInput textRangeFromPosition:closest toPosition:closest];
                    extendingSelection = kExtendingSelectionNone;
                }
                else if(result == NSOrderedAscending)
                {
                    activeTextInput.selectedTextRange = [activeTextInput textRangeFromPosition:closest toPosition:selectedTextRange.end];
                    extendingSelection = kExtendingSelectionAtStart;
                }

                selectionHasChanged = YES;
                
                CGRect newCaretRect = [activeTextInput caretRectForPosition:closest];
                
                int actualMovementY = (newCaretRect.origin.y - oldCaretRect.origin.y) / oldCaretRect.size.height;
                
                movementAccumulator = CGPointMake(movementAccumulator.x, movementAccumulator.y - actualMovementY);
            }
        }
    }
    
    [self removeTouchesInPhaseEnded:touchesForKeyboard];
    
    if(![self.keyboardTouches count])
    {
        movementAccumulator = CGPointZero;
        caretRectAfterXSelectionChange = CGRectZero;
        extendingSelection = kExtendingSelectionNone;
        
        if(activeTextInput)
        {
            if([activeTextInput comparePosition:[activeTextInput selectedTextRange].start toPosition:[activeTextInput selectedTextRange].end])
            {                
                [[UIMenuController sharedMenuController] setTargetRect:[activeTextInput firstRectForRange:[activeTextInput selectedTextRange]] inView:activeTextInput.textInputView];
                
                
                [[UIMenuController sharedMenuController] setMenuVisible:YES animated:YES];
            }
        }
    }
}

-(NSSet*)keyboardTouchesFromEvent:(UIEvent*)event
{
    NSSet * touchesForMainWindow = [event touchesForWindow:[[UIApplication sharedApplication] keyWindow]];
    NSMutableSet * touchesForKeyboard = [NSMutableSet setWithSet:[event allTouches]];
    [touchesForKeyboard minusSet:touchesForMainWindow];
    
    return touchesForKeyboard;
}

-(void)addTouchesInPhaseBegan:(NSSet*)touches atTime:(NSTimeInterval)time
{
    for (UITouch * touch in touches)
    {
        if (touch.phase == UITouchPhaseBegan)
        {
            selectionHasChanged = NO;
            
            [self.keyboardTouches addObject:touch];
            
            [self.keyboardTouchInfo setObject:[NSMutableArray arrayWithObject:[[[CDKeyboardTouchInfo alloc] initWithTime:time] autorelease]] forKey:[NSValue valueWithPointer:(const void*)touch]];
        }
    }
}

-(void)updateTouchesInPhaseMoved:(NSSet*)touches atTime:(NSTimeInterval)time
{
    for (UITouch * touch in touches)
    {
        if (touch.phase == UITouchPhaseMoved)
        {            
            NSMutableArray * touchInfoForTouch = [self.keyboardTouchInfo objectForKey:[NSValue valueWithPointer:(const void*)touch]];
            
            [touchInfoForTouch addObject:[[[CDKeyboardTouchInfo alloc] initWithMovement:[self movementForTouch:touch] time:time] autorelease]];
        }
    }
}

-(void)updateActiveTextInput
{
    if(![activeTextInput.textInputView isFirstResponder])
    {
        activeTextInput = nil;
        for(NSValue * value in [self.textInputs allKeys])
        {
            id<UITextInput> textInput = [value pointerValue];
            if([textInput.textInputView isFirstResponder])
            {
                activeTextInput = textInput;
                break;
            }
        }
    }
}

-(void)removeTouchesInPhaseEnded:(NSSet*)touches
{
    for (UITouch * touch in touches)
    {
        if (touch.phase == UITouchPhaseEnded || touch.phase == UITouchPhaseCancelled)
        {
            
            [self.keyboardTouches removeObject:touch];
            [self.keyboardTouchInfo removeObjectForKey:[NSValue valueWithPointer:(const void*)touch]];
        }
        else
        {
            [self removeOldTouchInfoFromTouch:touch];
        }
    }
}

#define VELOCITY_CALCULATION_DURATION (1.0f/20.f)

-(CGPoint)velocityForTouch:(UITouch*)touch
{
    NSMutableArray * touchInfoForTouch = [self.keyboardTouchInfo objectForKey:[NSValue valueWithPointer:(const void*)touch]];
    
    if([touchInfoForTouch count] < 2) return CGPointZero;
    
    CGPoint totalMovement = CGPointZero;
    
    CDKeyboardTouchInfo * mostRecent = [touchInfoForTouch lastObject];
    
    NSTimeInterval mostRecentTime = mostRecent.time;
    NSTimeInterval leastRecentTime = mostRecent.time;
    
    totalMovement = CGPointMake(totalMovement.x + mostRecent.movement.x, totalMovement.y + mostRecent.movement.y);
    
    for(int i = [touchInfoForTouch count] - 2; i >= 0; i--)
    {
        CDKeyboardTouchInfo * touchInfo = [touchInfoForTouch objectAtIndex:i];
        
        totalMovement = CGPointMake(totalMovement.x + touchInfo.movement.x, totalMovement.y + touchInfo.movement.y);
        leastRecentTime = touchInfo.time;
        
        if(touchInfo.time <= mostRecentTime - VELOCITY_CALCULATION_DURATION)
        {
            break;
        }
    }
    
    NSTimeInterval duration = mostRecentTime - leastRecentTime;
    return CGPointMake(totalMovement.x / duration, totalMovement.y / duration);
}

-(CGPoint)averageVelocityForKeyboardTouches
{
    CGPoint totalVelocity = CGPointZero;
    
    for(UITouch * touch in self.keyboardTouches)
    {
        CGPoint velocity = [self velocityForTouch:touch];
        
        totalVelocity = CGPointMake(totalVelocity.x + velocity.x, totalVelocity.y + velocity.y);
    }
    
    return CGPointMake(totalVelocity.x / [self.keyboardTouches count], totalVelocity.y / [self.keyboardTouches count]);
}

-(void)removeOldTouchInfoFromTouch:(UITouch*)touch
{
    NSMutableArray * touchInfoForTouch = [self.keyboardTouchInfo objectForKey:[NSValue valueWithPointer:(const void*)touch]];
    
    if([touchInfoForTouch count] < 2) return;
    
    CDKeyboardTouchInfo * mostRecent = [touchInfoForTouch lastObject];
    
    NSTimeInterval mostRecentTime = mostRecent.time;
    
    for(int i = [touchInfoForTouch count] - 2; i >= 0; i--)
    {
        CDKeyboardTouchInfo * touchInfo = [touchInfoForTouch objectAtIndex:i];
        
        if(touchInfo.time <= mostRecentTime - VELOCITY_CALCULATION_DURATION)
        {
            [touchInfoForTouch removeObject:touch];
        }
    }
}

-(CGPoint)movementForTouch:(UITouch*)touch
{
    CGPoint location = [touch locationInView:touch.view];
    CGPoint previousLocation = [touch previousLocationInView:touch.view];
    
    return CGPointMake(location.x - previousLocation.x, location.y - previousLocation.y);
}

-(float)selectionXChangeVelocityFromXTouchVelocity:(float)xTouchVelocity
{
#define DIVDER (350.f)
#define EXPONENT (1.8f)
    return xTouchVelocity > 0? powf(xTouchVelocity / DIVDER, EXPONENT) : -powf(fabsf(xTouchVelocity) / DIVDER, EXPONENT);
}

-(float)selectionYChangeVelocityFromYTouchVelocity:(float)yTouchVelocity
{
#undef DIVDER
#undef EXPONENT
#define DIVDER (600.f)
#define EXPONENT (1.6f)
    return yTouchVelocity > 0? powf(yTouchVelocity / DIVDER, EXPONENT) : -powf(fabsf(yTouchVelocity) / DIVDER, EXPONENT);
}


-(void)registerForKeyboardSelection:(id<UITextInput>)textInput
{    
    if([self.textInputs objectForKey:[NSValue valueWithPointer:(const void*)textInput]])
    {
        return;
    }
    
    id delegate = nil;
    
    if([textInput.textInputView isKindOfClass:[UITextView class]])
    {
        delegate = ((UITextView*)textInput.textInputView).delegate;
        ((UITextView*)textInput.textInputView).delegate = self;
    }
    else if([textInput.textInputView isKindOfClass:[UITextField class]])
    {
        delegate = ((UITextField*)textInput.textInputView).delegate;
        ((UITextField*)textInput.textInputView).delegate = self;
    }
    
    if(!delegate) delegate = [NSNull null];
    
    [self.textInputs setObject:delegate forKey:[NSValue valueWithPointer:(const void*)textInput]];
    
}

-(void)unregisterForKeyboardSelection:(id<UITextInput>)textInput
{
    id delegate = [self.textInputs objectForKey:textInput];
    
    if(delegate && delegate != [NSNull null])
    {
        if([textInput respondsToSelector:@selector(setDelegate:)])
        {
            [textInput performSelector:@selector(setDelegate:) withObject:delegate];
        }
    }
    
    [self.textInputs removeObjectForKey:[NSValue valueWithPointer:(const void*)textInput]];
}

#pragma mark - UITextView Delegate

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{            
    id<UITextViewDelegate> delegate = [self.textInputs objectForKey:[NSValue valueWithPointer:(const void*)textView]];
    
    if(!selectionHasChanged)
    {
        if([delegate conformsToProtocol:@protocol(UITextViewDelegate)] && [delegate respondsToSelector:@selector(textView:shouldChangeTextInRange:replacementText:)])
        {
            return [delegate textView:textView shouldChangeTextInRange:range replacementText:text];
        }
        else
        {
            return YES;
        }
    }
        
    return NO;
}

#pragma mark - UITextField Delegate


-(BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
    id<UITextFieldDelegate> delegate = [self.textInputs objectForKey:[NSValue valueWithPointer:(const void*)textField]];
    
    if(!selectionHasChanged)
    {
        if([delegate conformsToProtocol:@protocol(UITextFieldDelegate)] && [delegate respondsToSelector:@selector(textField:shouldChangeCharactersInRange:replacementString:)])
        {
            return [delegate textField:textField shouldChangeCharactersInRange:range replacementString:string];
        }
        else
        {
            return YES;
        }
    }
    
    
    return NO;
}


@end
