  ///////////////////////////////////////////////////////////////////////////
//
// The code for the red team
// ===========================
//
///////////////////////////////////////////////////////////////////////////

class RedTeam extends Team {
  final int MY_CUSTOM_MSG = 5;
  
  PVector base1, base2;

  // coordinates of the 2 bases, chosen in the rectangle with corners
  // (width/2, 0) and (width, height-100)
  RedTeam() {
    // first base
    base1 = new PVector(width/2 + 300, (height - 100)/2 - 150);
    // second base
    base2 = new PVector(width/2 + 300, (height - 100)/2 + 150);
  }  
}

interface RedRobot {
}

///////////////////////////////////////////////////////////////////////////
//
// The code for the green bases
//
///////////////////////////////////////////////////////////////////////////
class RedBase extends Base implements RedRobot {
  //
  // constructor
  // ===========
  //
  RedBase(PVector p, color c, Team t) {
    super(p, c, t);
  }

  //
  // setup
  // =====
  // > called at the creation of the base
  //
  void setup() {
    // creates a new harvester
    newHarvester();
    // 7 more harvesters to create
    brain[5].x = 7;
  }

  //
  // go
  // ==
  // > called at each iteration of the game
  // > defines the behavior of the agent
  //
  void go() {
    // handle received messages 
    handleMessages();

    // creates new robots depending on energy and the state of brain[5]
    if ((brain[5].x > 0) && (energy >= 1000 + harvesterCost)) {
      // 1st priority = creates harvesters 
      if (newHarvester())
        brain[5].x--;
    } else if ((brain[5].y > 0) && (energy >= 1000 + launcherCost)) {
      // 2nd priority = creates rocket launchers 
      if (newRocketLauncher())
        brain[5].y--;
    } else if ((brain[5].z > 0) && (energy >= 1000 + explorerCost)) {
      // 3rd priority = creates explorers 
      if (newExplorer())
        brain[5].z--;
    } else if (energy > 12000) {
      // if no robot in the pipe and enough energy 
      if ((int)random(2) == 0)
        // creates a new harvester with 50% chance
        brain[5].x++;
      else if ((int)random(2) == 0)
        // creates a new rocket launcher with 25% chance
        brain[5].y++;
      else
        // creates a new explorer with 25% chance
        brain[5].z++;
    }

    // creates new bullets and fafs if the stock is low and enought energy
    if ((bullets < 10) && (energy > 1000))
      newBullets(50);
    if ((fafs < 10) && (energy > 1000))
      newFafs(10);

    // OPTIMIZED SHOOTING BEHAVIOR
    // Priority 1: Target enemy bases (highest priority)
    Robot target = (Robot)minDist(perceiveRobots(ennemy, BASE));
    
    // Priority 2: Target enemy rocket launchers (dangerous threats)
    if (target == null) {
      target = (Robot)minDist(perceiveRobots(ennemy, LAUNCHER));
    }
    
    // Priority 3: Target harvester
    if (target == null) {
      target = (Robot)minDist(perceiveRobots(ennemy, HARVESTER));
    }

    // Priority 4: Target explorers
    if (target == null) {
      target = (Robot)minDist(perceiveRobots(ennemy));
    }
    
    // If a target is found
    if (target != null) {
      // Calculate predicted position based on target's movement
      PVector predictedPos = predictTargetPosition(target);
      
      // Calculate angle towards predicted position
      float shootAngle = atan2(predictedPos.y - pos.y, predictedPos.x - pos.x);
      heading = shootAngle;
      
      // Check if no friendly robots are in the line of fire
      ArrayList friendsInCone = perceiveRobotsInCone(friend, heading);
      
      if (friendsInCone == null || friendsInCone.size() == 0) {
        // Calculate distance to target
        float distToTarget = distance(target);

        if(target.breed == EXPLORER) 
        {
          // Don't waste ammo on explorers
          return;
        }
        else if(bullets >= 10 && (target.breed == BASE || distToTarget < basePerception * 0.8)) {
          // Use bullets for bases or close targets
          launchBullet(shootAngle);
        }
        else if(fafs > 0) {
          // Use fafs for other targets if available
          launchFaf(target);
        }
      }
    }
  }
  
  //
  // predictTargetPosition
  // =====================
  // > predicts where the target will be based on its current movement
  //
  // input
  // -----
  // > target = the enemy robot to track
  //
  // output
  // ------
  // > predicted position vector
  //
  PVector predictTargetPosition(Robot target) {
    // If target is stationary, return current position
    if (target.breed == BASE) 
    {
      return target.pos.copy();
    }

    // Calculate missile travel time (approximate)
    float distToTarget = distance(target);
    float missileSpeed = 1.0; // Typical speed of missiles
    float travelTime = distToTarget / missileSpeed;
    
    // Estimate target's velocity based on its heading and speed
    float targetVelocityX = cos(target.heading) * target.speed;
    float targetVelocityY = sin(target.heading) * target.speed;
    
    // Predict future position
    PVector predicted = new PVector(
      target.pos.x + targetVelocityX * travelTime,
      target.pos.y + targetVelocityY * travelTime
    );
    
    return predicted;
  }

  //
  // handleMessage
  // =============
  // > handle messages received since last activation 
  //
  void handleMessages() {
    Message msg;
    // for all messages
    for (int i=0; i<messages.size(); i++) {
      msg = messages.get(i);
      if (msg.type == ASK_FOR_ENERGY) {
        // if the message is a request for energy
        if (energy > 1000 + msg.args[0]) {
          // gives the requested amount of energy only if at least 1000 units of energy left after
          giveEnergy(msg.alice, msg.args[0]);
        }
      } else if (msg.type == ASK_FOR_BULLETS) {
        // if the message is a request for energy
        if (energy > 1000 + msg.args[0] * bulletCost) {
          // gives the requested amount of bullets only if at least 1000 units of energy left after
          giveBullets(msg.alice, msg.args[0]);
        }
      }
    }
    // clear the message queue
    flushMessages();
  }
}

///////////////////////////////////////////////////////////////////////////
//
// The code for the green explorers
//
///////////////////////////////////////////////////////////////////////////
// map of the brain:
//   4.x = (0 = exploration | 1 = go back to base)
//   4.y = (0 = no target | 1 = locked target)
//   0.x / 0.y = coordinates of the target
//   0.z = type of the target
///////////////////////////////////////////////////////////////////////////
class RedExplorer extends Explorer implements RedRobot {
  //
  // constructor
  // ===========
  //
  RedExplorer(PVector pos, color c, ArrayList b, Team t) {
    super(pos, c, b, t);
  }

  //
  // setup
  // =====
  // > called at the creation of the agent
  //
  void setup() {
  }

  //
  // go
  // ==
  // > called at each iteration of the game
  // > defines the behavior of the agent
  //
  void go() {
    // if food to deposit or too few energy
    if ((carryingFood > 200) || (energy < 100))
      // time to go back to base
      brain[4].x = 1;

    // depending on the state of the robot
    if (brain[4].x == 1) {
      // go back to base...
      goBackToBase();
    } else {
      // ...or explore randomly
      randomMove(45);
    }

    // tries to localize ennemy bases
    lookForEnnemyBase();
    // inform harvesters about food sources
    driveHarvesters();
    // inform rocket launchers about targets
    driveRocketLaunchers();

    // clear the message queue
    flushMessages();
  }

  //
  // setTarget
  // =========
  // > locks a target
  //
  // inputs
  // ------
  // > p = the location of the target
  // > breed = the breed of the target
  //
  void setTarget(PVector p, int breed) {
    brain[0].x = p.x;
    brain[0].y = p.y;
    brain[0].z = breed;
    brain[4].y = 1;
  }

  //
  // goBackToBase
  // ============
  // > go back to the closest base, either to deposit food or to reload energy
  //
  void goBackToBase() {
    // bob is the closest base
    Base bob = (Base)minDist(myBases);
    if (bob != null) {
      // if there is one (not all of my bases have been destroyed)
      float dist = distance(bob);

      if (dist <= 2) {
        // if I am next to the base
        if (energy < 500)
          // if my energy is low, I ask for some more
          askForEnergy(bob, 1500 - energy);
        // switch to the exploration state
        brain[4].x = 0;
        // make a half turn
        right(180);
      } else {
        // if still away from the base
        // head towards the base (with some variations)...
        heading = towards(bob) + random(-radians(20), radians(20));
        // ...and try to move forward 
        tryToMoveForward();
      }
    }
  }

  //
  // target
  // ======
  // > checks if a target has been locked
  //
  // output
  // ------
  // true if target locket / false if not
  //
  boolean target() {
    return (brain[4].y == 1);
  }

  //
  // driveHarvesters
  // ===============
  // > tell harvesters if food is localized
  //
  void driveHarvesters() {
    // look for burgers
    Burger zorg = (Burger)oneOf(perceiveBurgers());
    if (zorg != null) {
      // if one is seen, look for a friend harvester
      Harvester harvey = (Harvester)oneOf(perceiveRobots(friend, HARVESTER));
      if (harvey != null)
        // if a harvester is seen, send a message to it with the position of food
        informAboutFood(harvey, zorg.pos);
    }
  }

  //
  // driveRocketLaunchers
  // ====================
  // > tell rocket launchers about potential targets
  //
  void driveRocketLaunchers() {
    // look for an ennemy robot 
    Robot bob = (Robot)oneOf(perceiveRobots(ennemy));
    if (bob != null) {
      // if one is seen, look for a friend rocket launcher
      RocketLauncher rocky = (RocketLauncher)oneOf(perceiveRobots(friend, LAUNCHER));
      if (rocky != null)
        // if a rocket launcher is seen, send a message with the localized ennemy robot
        informAboutTarget(rocky, bob);
    }
  }

  //
  // lookForEnnemyBase
  // =================
  // > try to localize ennemy bases...
  // > ...and to communicate about this to other friend explorers
  //
  void lookForEnnemyBase() {
    // look for an ennemy base
    Base babe = (Base)oneOf(perceiveRobots(ennemy, BASE));
    if (babe != null) {
      // if one is seen, look for a friend explorer
      Explorer explo = (Explorer)oneOf(perceiveRobots(friend, EXPLORER));
      if (explo != null)
        // if one is seen, send a message with the localized ennemy base
        informAboutTarget(explo, babe);
      // look for a friend base
      Base basy = (Base)oneOf(perceiveRobots(friend, BASE));
      if (basy != null)
        // if one is seen, send a message with the localized ennemy base
        informAboutTarget(basy, babe);
    }
  }

  //
  // tryToMoveForward
  // ================
  // > try to move forward after having checked that no obstacle is in front
  //
  void tryToMoveForward() {
    // if there is an obstacle ahead, rotate randomly
    if (!freeAhead(speed))
      right(random(360));

    // if there is no obstacle ahead, move forward at full speed
    if (freeAhead(speed))
      forward(speed);
  }
}

///////////////////////////////////////////////////////////////////////////
//
// The code for the green harvesters
//
///////////////////////////////////////////////////////////////////////////
// map of the brain:
//   4.x = (0 = look for food | 1 = go back to base) 
//   4.y = (0 = no food found | 1 = food found)
//   0.x / 0.y = position of the localized food
///////////////////////////////////////////////////////////////////////////
class RedHarvester extends Harvester implements RedRobot {
  //
  // constructor
  // ===========
  //
  RedHarvester(PVector pos, color c, ArrayList b, Team t) {
    super(pos, c, b, t);
  }

  //
  // setup
  // =====
  // > called at the creation of the agent
  //
  void setup() {
  }

  //
  // go
  // ==
  // > called at each iteration of the game
  // > defines the behavior of the agent
  //
  void go() {
    // handle messages received
    handleMessages();

    // check for the closest burger
    Burger b = (Burger)minDist(perceiveBurgers());
    if ((b != null) && (distance(b) <= 2))
      // if one is found next to the robot, collect it
      takeFood(b);

    // if food to deposit or too few energy
    if ((carryingFood > 200) || (energy < 100))
      // time to go back to the base
      brain[4].x = 1;

    // if in "go back" state
    if (brain[4].x == 1) {
      // go back to the base
      goBackToBase();

      // if enough energy and food
      if ((energy > 100) && (carryingFood > 100)) {
        // check for closest base
        Base bob = (Base)minDist(myBases);
        if (bob != null) {
          // if there is one and the harvester is in the sphere of perception of the base
          if (distance(bob) < basePerception)
            // plant one burger as a seed to produce new ones
            plantSeed();
        }
      }
    } else
      // if not in the "go back" state, explore and collect food
      goAndEat();
  }

  //
  // goBackToBase
  // ============
  // > go back to the closest friend base
  //
  void goBackToBase() {
    // look for the closest base
    Base bob = (Base)minDist(myBases);
    if (bob != null) {
      // if there is one
      float dist = distance(bob);
      if ((dist > basePerception) && (dist < basePerception + 1))
        // if at the limit of perception of the base, drops a wall (if it carries some)
        dropWall();

      if (dist <= 2) {
        // if next to the base, gives the food to the base
        giveFood(bob, carryingFood);
        if (energy < 500)
          // ask for energy if it lacks some
          askForEnergy(bob, 1500 - energy);
        // go back to "explore and collect" mode
        brain[4].x = 0;
        // make a half turn
        right(180);
      } else {
        // if still away from the base
        // head towards the base (with some variations)...
        heading = towards(bob) + random(-radians(20), radians(20));
        // ...and try to move forward
        tryToMoveForward();
      }
    }
  }

  //
  // goAndEat
  // ========
  // > go explore and collect food
  //
  void goAndEat() {
    // look for the closest wall
    Wall wally = (Wall)minDist(perceiveWalls());
    // look for the closest base
    Base bob = (Base)minDist(myBases);
    if (bob != null) {
      float dist = distance(bob);
      // if wall seen and not at the limit of perception of the base 
      if ((wally != null) && ((dist < basePerception - 1) || (dist > basePerception + 2)))
        // tries to collect the wall
        takeWall(wally);
    }

    // look for the closest burger
    Burger zorg = (Burger)minDist(perceiveBurgers());
    if (zorg != null) {
      // if there is one
      if (distance(zorg) <= 2)
        // if next to it, collect it
        takeFood(zorg);
      else {
        // if away from the burger, head towards it...
        heading = towards(zorg) + random(-radians(20), radians(20));
        // ...and try to move forward
        tryToMoveForward();
      }
    } else if (brain[4].y == 1) {
      // if no burger seen but food localized (thank's to a message received)
      if (distance(brain[0]) > 2) {
        // head towards localized food...
        heading = towards(brain[0]);
        // ...and try to move forward
        tryToMoveForward();
      } else
        // if the food is reached, clear the corresponding flag
        brain[4].y = 0;
    } else {
      // if no food seen and no food localized, explore randomly
      heading += random(-radians(45), radians(45));
      tryToMoveForward();
    }
  }

  //
  // tryToMoveForward
  // ================
  // > try to move forward after having checked that no obstacle is in front
  //
  void tryToMoveForward() {
    // if there is an obstacle ahead, rotate randomly
    if (!freeAhead(speed))
      right(random(360));

    // if there is no obstacle ahead, move forward at full speed
    if (freeAhead(speed))
      forward(speed);
  }

  //
  // handleMessages
  // ==============
  // > handle messages received
  // > identify the closest localized burger
  //
  void handleMessages() {
    float d = width;
    PVector p = new PVector();

    Message msg;
    // for all messages
    for (int i=0; i<messages.size(); i++) {
      // get next message
      msg = messages.get(i);
      // if "localized food" message
      if (msg.type == INFORM_ABOUT_FOOD) {
        // record the position of the burger
        p.x = msg.args[0];
        p.y = msg.args[1];
        if (distance(p) < d) {
          // if burger closer than closest burger
          // record the position in the brain
          brain[0].x = p.x;
          brain[0].y = p.y;
          // update the distance of the closest burger
          d = distance(p);
          // update the corresponding flag
          brain[4].y = 1;
        }
      }
    }
    // clear the message queue
    flushMessages();
  }
}

///////////////////////////////////////////////////////////////////////////
//
// The code for the red rocket launchers
//
///////////////////////////////////////////////////////////////////////////
// map of the brain:
//   0.x / 0.y = position of the target
//   0.z = breed of the target
//   4.x = (0 = look for target | 1 = go back to base) 
//   4.y = (0 = no target | 1 = localized target)
//   1.x / 1.y = predicted target position for shooting
//   2.x = distance to target
///////////////////////////////////////////////////////////////////////////
class RedRocketLauncher extends RocketLauncher implements RedRobot {
  //
  // constructor
  // ===========
  //
  RedRocketLauncher(PVector pos, color c, ArrayList b, Team t) {
    super(pos, c, b, t);
  }

  //
  // setup
  // =====
  // > called at the creation of the agent
  //
  void setup() {
  }

  //
  // go
  // ==
  // > called at each iteration of the game
  // > defines the behavior of the agent
  //
  void go() {
    // if no energy or no bullets, go back to base
    if ((energy < 300) || (bullets == 0)) {
      brain[4].x = 1;
    }

    // OPTIMIZED TARGET SELECTION with priority system
    selectTargetWithPriority();
      
    if (brain[4].x == 1)
    {
      // go back to base
      goBackToBase();
    }
    else if(hasTarget()) {
      // Pursue and shoot the target
      pursueAndShoot();
    } else {
      // else explore randomly
      randomMove(45);
    }
  }

  //
  // selectTargetWithPriority
  // ========================
  // > select target based on priority system:
  // > 1. Bases (highest priority)
  // > 2. Harvesters (economic targets)
  // > 3. Rocket Launchers (only if we have advantage)
  // > 4. Explorers (lowest priority)
  //
  void selectTargetWithPriority() {
    Robot bob = null;
    
    // Priority 1: Enemy bases (highest priority)
    bob = (Robot)minDist(perceiveRobots(ennemy, BASE));
    
    // Priority 2: Enemy harvesters (economic targets)
    if (bob == null) {
      bob = (Robot)minDist(perceiveRobots(ennemy, HARVESTER));
    }
    
    // Priority 3: Enemy rocket launchers (only if we have advantage)
    if (bob == null) {
      Robot enemyLauncher = (Robot)minDist(perceiveRobots(ennemy, LAUNCHER));
      if (enemyLauncher != null) {
        // Only engage if we are sure to win
        if(enemyLauncher.bullets * bulletDamageToRobot < energy &&
        bullets * bulletDamageToRobot > enemyLauncher.energy) {
          bob = enemyLauncher;
        }
        // Retreat
        else
        {
          brain[4].x = 1; // Go back to base
          brain[4].y = 0; // Clear target lock
          return;
        }
      }
    }
    
    // Priority 4: Enemy explorers not close to base (lowest priority)
    if (bob == null) {
      bob = (Robot)minDist(perceiveRobots(ennemy, EXPLORER));

      // Ignore explorers that are too close to our bases (we trap them)
      if (bob != null) {
        Base nearestBase = (Base)minDist(myBases);
        if (nearestBase != null) {
          float distToBase = bob.distance(nearestBase);
          if (distToBase < basePerception * 0.2) {
            bob = null;
          }
        }
      }
    }
    
    if (bob != null) {
      // Target found - record position, breed, and distance
      brain[0].x = bob.pos.x;
      brain[0].y = bob.pos.y;
      brain[0].z = bob.breed;
      brain[2].x = distance(bob);
      
      // Calculate predicted position for accurate shooting
      PVector predicted = predictTargetPosition(bob);
      brain[1].x = predicted.x;
      brain[1].y = predicted.y;
      
      // Lock the target
      brain[4].y = 1;
    } else {
      // No target found
      brain[4].y = 0;
    }
  }

  //
  // predictTargetPosition
  // =====================
  // > predicts where the target will be when bullet arrives
  //
  // input
  // -----
  // > target = the enemy robot to track
  //
  // output
  // ------
  // > predicted position vector
  //
  PVector predictTargetPosition(Robot target) {
    // If target is a base (stationary), return current position
    if (target.breed == BASE) {
      return target.pos.copy();
    }
    
    // Calculate distance to target
    float distToTarget = distance(target);
    
    // Bullet travel time
    float bulletTravelTime = distToTarget / bulletSpeed;
    
    // Estimate target's future position based on velocity
    float targetVelocityX = cos(target.heading) * target.speed;
    float targetVelocityY = sin(target.heading) * target.speed;
    
    // Predict position with lead
    PVector predicted = new PVector(
      target.pos.x + targetVelocityX * bulletTravelTime,
      target.pos.y + targetVelocityY * bulletTravelTime
    );
    
    return predicted;
  }

    //
  // pursueAndShoot
  // ==============
  // > pursue the target and shoot as much as possible
  //
  void pursueAndShoot() {
    // Get current target position (updated by selectTargetWithPriority)
    PVector targetPos = new PVector(brain[0].x, brain[0].y);
    float distToTarget = distance(targetPos);
    
    // Get predicted position for shooting
    PVector predictedPos = new PVector(brain[1].x, brain[1].y);
    
    // FIXED: Use towards() method which handles wrapping correctly
    float angleToTarget = towards(predictedPos);
    
    // OPTIMIZED MOVEMENT with minimum safe distance
    float optimalDistance = launcherPerception * 0.7;  // Optimal shooting distance
    float minSafeDistance = 1.0;  // Minimum distance to avoid passing through
    
    if (distToTarget > optimalDistance) {
      // Too far - move closer aggressively
      // FIXED: Use towards() for movement direction as well
      heading = towards(targetPos);
      tryToMoveForward();
    } 
    else if (distToTarget < minSafeDistance) {
      // TOO CLOSE - RETREAT to safe distance
      // Move backwards while keeping target in sight
      // FIXED: Use towards() and add PI to go opposite direction
      heading = towards(targetPos) + PI;  // Opposite direction
      if (freeAhead(speed)) {
        forward(speed);
      } else {
        // If blocked, strafe to the side
        right(90);
        if (freeAhead(speed)) {
          forward(speed);
        }
      }
    }
    else if (distToTarget < optimalDistance * 0.8) {
      // Still a bit too close - maintain distance or retreat slowly
      heading = angleToTarget;  // Face target
      // Don't move forward, just adjust angle
    }
    else {
      // Perfect distance range - maintain position and focus on shooting
      heading = angleToTarget;
      
      // Small adjustments to keep optimal distance
      if (distToTarget > optimalDistance) {
        if (freeAhead(speed * 0.3)) {
          forward(speed * 0.3);
        }
      }
    }
    
    // SHOOTING - only shoot if at safe distance
    if (distToTarget >= minSafeDistance) {
      ArrayList friendsInCone = perceiveRobotsInCone(friend, angleToTarget);
      
      if (friendsInCone == null || friendsInCone.size() == 0) {
        heading = angleToTarget;
        launchBullet(angleToTarget);
      }
    }
  }

  //
  // target
  // ======
  // > checks if a target has been locked
  //
  // output
  // ------
  // > true if target locked / false if not
  //
  boolean hasTarget() {
    return (brain[4].y == 1);
  }

  //
  // goBackToBase
  // ============
  // > go back to the closest base
  //
  void goBackToBase() {
    // look for closest base
    Base bob = (Base)minDist(myBases);
    if (bob != null) {
      // if there is one, compute its distance
      float dist = distance(bob);

      if (dist <= 2) {
        // if next to the base
        if (energy < 500) {
          // if energy low, ask for some energy
          askForEnergy(bob, 1500 - energy);
        }
        
        // Request bullets if empty or low
        if (bullets < launcherMaxBullets * 0.8) {
          askForBullets(bob, launcherMaxBullets - bullets);
        }
        
        // Only leave base if both energy and bullets are good
        if (energy >= 500 && bullets >= launcherMaxBullets * 0.5) {
          // go back to "combat" mode
          brain[4].x = 0;
          // make a half turn
          right(180);
        }
      } else {
        // if not next to the base, head towards it... 
        heading = towards(bob) + random(-radians(20), radians(20));
        // ...and try to move forward
        tryToMoveForward();
      }
    }
  }

  //
  // tryToMoveForward
  // ================
  // > try to move forward after having checked that no obstacle is in front
  //
  void tryToMoveForward() {
    // if there is an obstacle ahead, rotate randomly
    if (!freeAhead(speed))
      right(random(360));

    // if there is no obstacle ahead, move forward at full speed
    if (freeAhead(speed))
      forward(speed);
  }
}