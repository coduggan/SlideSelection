### What's it?

SlideSelection is inspired by [Daniel Hooper's Video](http://www.youtube.com/watch?v=RGQTaHGQ04Q "Hooper Selection (iPad Keyboard Prototype)") on how to improve editing text on the iPad by using gestures over the keyboard to manipulate the cursor and text selection.

SlideSelection allows you to move the cursor left, right, up or down using a one finger drag. A two-finger drag will select text instead.


### How to use in your application

**Subclass UIApplication**

-Create a class which is a subclass of UIApplication. This can be as simple as changing your AppDelegate's superclass from UIResponder to UIApplication.

-#import "CDKeyboardSelectionManager.h"

-Override the sendEvent: method.

		- (void)sendEvent:(UIEvent *)event
		{
				[super sendEvent:event];

		    [[CDKeyboardSelectionManager sharedManager] handleEvent:event];
		}

**Update main.m if needed**

-In main.m, make sure the third argument of UIApplicationMain is the name of the subclass.

		return UIApplicationMain(argc, argv, NSStringFromClass([AppDelegate class]), nil);

**Register your text inputs**

-For any text input (UITextView, UITextField etc.) that you want to use Hooper Selection, you must register it with the CDKeyboardSelectionManager.

		[[CDKeyboardSelectionManager sharedManager] registerForKeyboardSelection:textView];
    
-If you no longer want that text input to use Hooper Selection, you can unregister it.

		[[CDKeyboardSelectionManager sharedManager] unregisterForKeyboardSelection:textView];
		
**Requires iOS 5**

