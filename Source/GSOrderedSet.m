/** Concrete implementation of GSOrderedSet based on GNU Set class
    Copyright (C) 2019 Free Software Foundation, Inc.
    
    Written by: Gregory Casamento <greg.casamento@gmail.com>
    Created: May 17 2019
    
    This file is part of the GNUstep Base Library.
    
    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Lesser General Public
    License as published by the Free Software Foundation; either
    _version 2 of the License, or (at your option) any later _version.
    
    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Library General Public License for more details.
    
    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free
    Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
    Boston, MA 02111 USA.
*/

#import "common.h"
#import "Foundation/NSOrderedSet.h"
#import "Foundation/NSAutoreleasePool.h"
#import "Foundation/NSArray.h"
#import "Foundation/NSEnumerator.h"
#import "Foundation/NSException.h"
#import "Foundation/NSPortCoder.h"
#import "Foundation/NSIndexSet.h"
#import "Foundation/NSKeyedArchiver.h"
#import "Foundation/NSValue.h"
#import "Foundation/NSDictionary.h"
#import "GNUstepBase/GSObjCRuntime.h"
#import "GSPrivate.h"
#import "GSFastEnumeration.h"
#import "GSDispatch.h"
#import "GSSorting.h"

#define	GSI_ARRAY_TYPE	NSRange
#define	GSI_ARRAY_NO_RELEASE	1
#define	GSI_ARRAY_NO_RETAIN	1
#define GSI_ARRAY_TYPES       GSUNION_OBJ

#define GSI_ARRAY_RELEASE(A, X)	[(X).obj release]
#define GSI_ARRAY_RETAIN(A, X)	[(X).obj retain]

#import "GNUstepBase/GSIArray.h"

@interface GSOrderedSet : NSOrderedSet
{
@public
  GSIArray_t array;
}
@end

@interface GSMutableOrderedSet : NSMutableOrderedSet
{
@public
  GSIArray_t array;
@private
  NSUInteger _version;
}
@end

@interface GSOrderedSetEnumerator : NSEnumerator
{
  GSOrderedSet *set;
  unsigned      current;
  unsigned      count;
}
@end

@interface GSOrderedSetEnumeratorReverse : GSOrderedSetEnumerator
@end

@implementation GSOrderedSetEnumerator
- (id) initWithOrderedSet: (NSOrderedSet*)d
{
  self = [super init];
  if (self != nil)
    {
      set = (GSOrderedSet*)RETAIN(d);
      current = 0;
      count = GSIArrayCount(&set->array);
    }
  return self;
}

- (id) nextObject
{
  if(current < count)
    {
      GSIArrayItem item = GSIArrayItemAtIndex(&set->array, current);
      current++;
      return (id)(item.obj);
    }
  return nil;
}

- (void) dealloc
{
  RELEASE(set);
  [super dealloc];
}
@end


@implementation GSOrderedSetEnumeratorReverse
- (id) initWithOrderedSet: (GSOrderedSet*)d
{
  self = [super initWithOrderedSet: d];
  if(self != nil)
    {
      current = GSIArrayCount(&set->array);
    }
  return self;
}

- (id) nextObject
{
  GSIArrayItem item;

  if (current == 0)
    return nil;
  
  item = GSIArrayItemAtIndex(&set->array, --current);
  return (id)(item.obj);
}
@end

@implementation GSOrderedSet

static Class	setClass;
static Class	mutableSetClass;

+ (void) initialize
{
  if (self == [GSOrderedSet class])
    {
      setClass = [GSOrderedSet class];
      mutableSetClass = [GSMutableOrderedSet class];
    }
}

- (id) copyWithZone: (NSZone*)z
{
  return RETAIN(self);
}

- (void) dealloc
{
  GSIArrayEmpty(&array);
  [super dealloc];
}

- (NSUInteger) hash
{
  return [self count];
}

- (id) init
{
  return [self initWithObjects: NULL count: 0];
}

- (NSEnumerator*) objectEnumerator
{
  return AUTORELEASE([[GSOrderedSetEnumerator alloc] initWithOrderedSet: self]);
}

- (NSEnumerator*) reverseObjectEnumerator
{
  return AUTORELEASE([[GSOrderedSetEnumeratorReverse alloc] initWithOrderedSet: self]);
}

- (NSUInteger) countByEnumeratingWithState: (NSFastEnumerationState*)state
                                   objects: (id*)stackbuf
                                     count: (NSUInteger)len
{
  //state->mutationsPtr = (unsigned long *)self;
  //return GSIMapCountByEnumeratingWithStateObjectsCount
  //            (&map, state, stackbuf, len);

  return [self count];
}

- (NSUInteger) sizeInBytesExcluding: (NSHashTable*)exclude
{
  NSUInteger	size = GSPrivateMemorySize(self, exclude);

  if (size > 0)
    {
      NSUInteger count = [self count];
      NSUInteger i = 0;

      for(i = 0; i < count; i++)
	{
	  GSIArrayItem item = GSIArrayItemAtIndex(&array, i);
          size += [item.obj sizeInBytesExcluding: exclude];
        }
    }
  return size;
}

// Put required overrides here...
- (NSUInteger) count
{
  return GSIArrayCount(&array);
}

- (id) objectAtIndex: (NSUInteger)index
{
  GSIArrayItem item = GSIArrayItemAtIndex(&array, index);
  return item.obj;
}

/* Designated initialiser */
- (id) initWithObjects: (const id*)objs count: (NSUInteger)c
{
  NSUInteger i = 0;

  // Initialize and fill the set.
  GSIArrayInitWithZoneAndCapacity(&array, [self zone], c);
  for (i = 0; i < c; i++)
    {
      id obj = objs[i];
      GSIArrayItem item;
      
      if (objs[i] == nil)
	{
	  DESTROY(self);
	  [NSException raise: NSInvalidArgumentException
		      format: @"Tried to init set with nil value"];
	}

      item.obj = obj;
      if(![self containsObject: obj])
	{
	  GSIArrayAddItem(&array, item);
	  RETAIN(obj);
	}
    }
  return self;
}

@end

@implementation GSMutableOrderedSet

+ (void) initialize
{
  if (self == [GSMutableOrderedSet class])
    {
      GSObjCAddClassBehavior(self, [GSOrderedSet class]);
    }
}

- (void) addObject: (id)anObject
{
  GSIArrayItem item;

  if (anObject == nil)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"Tried to add nil to set"];
    }

  if([self containsObject: anObject] == NO)
    {
      item.obj = anObject;
      GSIArrayAddItem(&array, item);
      RETAIN(anObject);
      _version++;
    }
}

- (void) insertObject: (id)object atIndex: (NSUInteger)index
{
  GSIArrayItem item;
  if([self containsObject: object] == NO)
    {
      item.obj = object;
      GSIArrayInsertItem(&array, item, index);
      RETAIN(object);
      _version++;
    }
}

- (void) _insertObject: (id)object atIndex: (NSUInteger)index
{
  GSIArrayItem item;
  
  item.obj = object;
  GSIArrayInsertItem(&array, item, index);
  RETAIN(object);
  _version++;
}

- (void) removeObjectAtIndex: (NSUInteger)index
{
  _version++;
  GSIArrayRemoveItemAtIndex(&array, index);
}

- (void) replaceObjectAtIndex: (NSUInteger)index
		   withObject: (id)obj
{
  [self _insertObject: obj atIndex: index];
  [self removeObjectAtIndex: index];
}

- (id) init
{
  return [self initWithCapacity: 0];
}

/* Designated initialiser */
- (id) initWithCapacity: (NSUInteger)cap
{
  GSIArrayInitWithZoneAndCapacity(&array, [self zone], cap);
  return self;
}

- (id) initWithObjects: (const id*)objects
		 count: (NSUInteger)count
{
  NSUInteger i = 0;

  // Init and fill set
  self = [self initWithCapacity: count];
  if(self != nil)
    {
      for(i = 0; i < count; i++)
	{
	  id	anObject = objects[i];	  
	  if (anObject == nil)
	    {
	      NSLog(@"Tried to init an orderedset with a nil object");
	      continue;
	    }
	  else
	    {
	      GSIArrayItem item;
	      if(![self containsObject: anObject])
		{
		  item.obj = anObject;
		  GSIArrayAddItem(&array, item);
		  RETAIN(anObject);
		}
	    }
	}
    }
  return self;
}

- (BOOL) makeImmutable
{
  GSClassSwizzle(self, [GSOrderedSet class]);
  return YES;
}

- (id) makeImmutableCopyOnFail: (BOOL)force
{
  GSClassSwizzle(self, [GSOrderedSet class]);
  return self;
}

- (NSUInteger) countByEnumeratingWithState: (NSFastEnumerationState*)state
                                   objects: (id*)stackbuf
                                     count: (NSUInteger)len
{
  //state->mutationsPtr = (unsigned long *)&_version;
  //return GSIMapCountByEnumeratingWithStateObjectsCount
  //  (&map, state, stackbuf, len);
  return [self count];
}
@end
