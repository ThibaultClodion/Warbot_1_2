  ///////////////////////////////////////////////////////////////////////////
//
// The code for the red team
// ===========================
//
///////////////////////////////////////////////////////////////////////////

class RedTeam extends Team {
  static final int HARVESTER_FULL = 5;
  
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
// The code for the red bases
//
///////////////////////////////////////////////////////////////////////////
// map of the brain:
//   0.x / 0.y = position of known enemy base
//   0.z = (0 = no enemy base known | 1 = enemy base known)
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
    // 2 rocket launchers to create
    brain[5].y = 2;
    // 1 explorer to create
    brain[5].z = 1;
    // No enemy base known at start
    brain[0].z = 0;
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

    // Broadcast enemy base location to nearby allies
    if (brain[0].z == 1) {
      broadcastEnemyBaseLocation();
    }

    // creates new robots depending on energy and the state of brain[5]
    if ((brain[5].x > 0) && (energy >= 1000 + harvesterCost)) {
      // 1st priority = creates harvesters 
      if (newHarvester())
        brain[5].x--;
    } else if ((brain[5].y > 0) && (energy >= 1000 + launcherCost)) {
      // 2nd priority = creates rocket launchers 
      if (newRocketLauncher())
      {
        brain[5].y--;
      }
    } else if ((brain[5].z > 0) && (energy >= 1000 + explorerCost)) {
      // 3rd priority = creates explorers 
      if (newExplorer())
        brain[5].z--;
    } else if (energy > 10000) {
      // if no robot in the pipe and enough energy 
      if ((int)random(2) == 0)
        // creates a new harvester with 50% chance
        brain[5].x++;
      else
        // creates a new rocket launcher with 50% chance
        brain[5].y++;
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
  // broadcastEnemyBaseLocation
  // ==========================
  // > broadcast enemy base location to all friendly robots in perception range
  //
  void broadcastEnemyBaseLocation() {
    PVector enemyBasePos = new PVector(brain[0].x, brain[0].y);
    
    // Inform all rocket launchers in range
    ArrayList launchers = perceiveRobots(friend, LAUNCHER);
    if (launchers != null) {
      for (int i = 0; i < launchers.size(); i++) {
        Robot launcher = (Robot)launchers.get(i);
        informAboutTarget(launcher, enemyBasePos, BASE);
      }
    }
    
    // Inform all explorers in range
    ArrayList explorers = perceiveRobots(friend, EXPLORER);
    if (explorers != null) {
      for (int i = 0; i < explorers.size(); i++) {
        Robot explorer = (Robot)explorers.get(i);
        informAboutTarget(explorer, enemyBasePos, BASE);
      }
    }
  }
  
  //
  // informAboutTarget
  // =================
  // > send a message to a robot with position and breed of a target
  //
  // inputs
  // ------
  // > r = the robot to inform
  // > targetPos = position of the target
  // > breed = breed of the target
  //
  void informAboutTarget(Robot r, PVector targetPos, int breed) {
    float[] args = new float[3];
    args[0] = targetPos.x;
    args[1] = targetPos.y;
    args[2] = breed;
    sendMessage(r, INFORM_ABOUT_TARGET, args);
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
  // handleMessages
  // ==============
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
        // if the message is a request for bullets
        if (energy > 1000 + msg.args[0] * bulletCost) {
          // gives the requested amount of bullets only if at least 1000 units of energy left after
          giveBullets(msg.alice, msg.args[0]);
        }
      } else if (msg.type == INFORM_ABOUT_TARGET) {
        // if the message is about an enemy target
        int targetBreed = (int)msg.args[2];
        if (targetBreed == BASE) {
          // Store enemy base position
          brain[0].x = msg.args[0];
          brain[0].y = msg.args[1];
          brain[0].z = 1; // Mark that we know enemy base location
        }
      }
    }
    // clear the message queue
    flushMessages();
  }
}

///////////////////////////////////////////////////////////////////////////
//
// The code for the red explorers
//
///////////////////////////////////////////////////////////////////////////
// map of the brain:
//   4.x = (0 = westward exploration | 1 = return to base with intel | 2 = support mode near base)
//   4.y = (0 = no enemy base known | 1 = enemy base known)
//   0.x / 0.y = coordinates of enemy base
//   0.z = (0 = info not transmitted | 1 = info transmitted)
//   1.x / 1.y = position of home base
//   2.x = distance traveled during exploration
//   3.x / 3.y = patrol position around the base
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
    brain[4].x = 0; // Westward exploration mode
    brain[4].y = 0; // No enemy base known
    brain[0].z = 0; // Info not transmitted
    brain[2].x = 0; // Distance traveled
    
    // Record the spawn base position (closest base)
    Base homeBase = (Base)minDist(myBases);
    if (homeBase != null) {
      brain[1].x = homeBase.pos.x;
      brain[1].y = homeBase.pos.y;
    }
    
    // Initial direction westward (west = PI radians)
    heading = PI;
  }

  //
  // go
  // ==
  // > called at each iteration of the game
  // > defines the behavior of the agent
  //
  void go() {
    // Always look for enemy base in exploration mode
    if (brain[4].x == 0) {
      lookForEnemyBase();
    }
    
    // If enemy base found and not yet reported
    if (brain[4].y == 1 && brain[0].z == 0) {
      brain[4].x = 1; // Switch to return mode
    }
    
    // Energy management - return if too low
    if (energy < 200 && brain[4].x != 2) {
      brain[4].x = 1; // Return to base
    }
    
    // Inform nearby rocket launchers about enemy base if known
    if (brain[4].y == 1) {
      informRocketLaunchersAboutEnemyBase();
    }
    
    // Execute behavior based on mode
    if (brain[4].x == 0) {
      // Westward exploration mode
      exploreWestward();
    } else if (brain[4].x == 1) {
      // Return to base with intel mode
      returnToHomeBase();
    } else if (brain[4].x == 2) {
      // Support mode near base
      supportNearBase();
    }
    
    // clear the message queue
    flushMessages();
  }

  //
  // exploreWestward
  // ===============
  // > explore westward looking for enemy base
  //
  void exploreWestward() {
    // Main direction westward with small variations
    heading = PI + random(-radians(20), radians(20));
    
    // Increment distance traveled
    brain[2].x += speed;
    
    // Try to move forward
    tryToMoveForward();
  }

  //
  // returnToHomeBase
  // ================
  // > return to home base to transmit intel
  //
  void returnToHomeBase() {
    PVector homeBasePos = new PVector(brain[1].x, brain[1].y);
    float dist = distance(homeBasePos);
    
    if (dist <= basePerception) {
      // Within base range - transmit intel
      Base homeBase = (Base)minDist(myBases);
      if (homeBase != null && brain[0].z == 0) {
        transmitEnemyBaseIntel(homeBase);
        brain[0].z = 1; // Mark as transmitted
      }
      
      // Switch to support mode near base
      brain[4].x = 2;
      
      // Reload if necessary
      if (energy < 500 && homeBase != null) {
        if (distance(homeBase) <= 2) {
          askForEnergy(homeBase, 1000 - energy);
        } else {
          heading = towards(homeBase);
          tryToMoveForward();
        }
      }
    } else {
      // Head towards home base
      heading = towards(homeBasePos);
      tryToMoveForward();
    }
  }

  //
  // supportNearBase
  // ===============
  // > stay near ally base to support harvesters
  //
  void supportNearBase() {
    PVector homeBasePos = new PVector(brain[1].x, brain[1].y);
    float distToBase = distance(homeBasePos);
    
    // Patrol radius around base (within perception perimeter)
    float patrolRadius = basePerception * 0.7;
    
    // Accept food transfers from harvesters
    handleFoodTransferFromHarvesters();
    
    // Inform harvesters about nearby food
    informHarvestersAboutNearbyFood();
    
    // If too far from base, return
    if (distToBase > patrolRadius * 1.5) {
      heading = towards(homeBasePos);
      tryToMoveForward();
    }
    // If too close, move away a bit
    else if (distToBase < patrolRadius * 0.3) {
      heading = towards(homeBasePos) + PI; // Opposite direction
      tryToMoveForward();
    }
    // Correct distance - patrol in circle
    else {
      // Patrol around the base
      heading = towards(homeBasePos) + HALF_PI;
      tryToMoveForward();
    }
    
    // Reload if energy is low
    if (energy < 300) {
      Base homeBase = (Base)minDist(myBases);
      if (homeBase != null) {
        float dist = distance(homeBase);
        if (dist <= 2) {
          askForEnergy(homeBase, 1000 - energy);
        } else if (dist < basePerception) {
          heading = towards(homeBase);
          tryToMoveForward();
        }
      }
    }
  }

  //
  // informRocketLaunchersAboutEnemyBase
  // ===================================
  // > inform all nearby rocket launchers about enemy base location
  //
  void informRocketLaunchersAboutEnemyBase() {
    // Get all nearby rocket launchers
    ArrayList launchers = perceiveRobots(friend, LAUNCHER);
    
    if (launchers != null) {
      // Enemy base position
      PVector enemyBasePos = new PVector(brain[0].x, brain[0].y);
      
      // Inform each rocket launcher
      for (int i = 0; i < launchers.size(); i++) {
        RocketLauncher launcher = (RocketLauncher)launchers.get(i);
        informAboutTarget(launcher, enemyBasePos, BASE);
      }
    }
  }

  //
  // informAboutTarget
  // =================
  // > send a message to a robot with position and breed of a target
  //
  // inputs
  // ------
  // > r = the robot to inform
  // > targetPos = position of the target
  // > breed = breed of the target
  //
  void informAboutTarget(Robot r, PVector targetPos, int breed) {
    float[] args = new float[3];
    args[0] = targetPos.x;
    args[1] = targetPos.y;
    args[2] = breed;
    sendMessage(r, INFORM_ABOUT_TARGET, args);
  }

  //
  // informHarvestersAboutNearbyFood
  // ===============================
  // > inform all nearby harvesters about food found
  //
  void informHarvestersAboutNearbyFood() {
    // Look for nearby food
    Burger food = (Burger)minDist(perceiveBurgers());
    
    if (food != null) {
      // Inform all harvesters in range
      ArrayList harvesters = perceiveRobots(friend, HARVESTER);
      if (harvesters != null) {
        for (int i = 0; i < harvesters.size(); i++) {
          Harvester harvey = (Harvester)harvesters.get(i);
          // Only inform if harvester is not already full
          if (harvey.carryingFood < 150) {
            informAboutFood(harvey, food.pos);
          }
        }
      }
    }
  }

  //
  // handleFoodTransferFromHarvesters
  // ================================
  // > handle food transfers from harvesters
  //
  void handleFoodTransferFromHarvesters() {
    // Look for nearby harvesters with lots of food
    ArrayList harvesters = perceiveRobots(friend, HARVESTER);
    
    if (harvesters != null) {
      for (int i = 0; i < harvesters.size(); i++) {
        Harvester harv = (Harvester)harvesters.get(i);
        
        // If harvester has lots of food and we have capacity
        if (harv.carryingFood > 150 && carryingFood < 100) {
          float dist = distance(harv);
          
          if (dist <= 2) {
            // Next to harvester - it can transfer food to us
            // Harvester will use giveFood on us
            return; // Stay here to receive
          } else if (dist < explorerPerception * 0.4) {
            // Nearby harvester needs help - go towards it
            heading = towards(harv);
            tryToMoveForward();
            return;
          }
        }
      }
    }
    
    // If carrying food, bring it back to base
    if (carryingFood > 100) {
      Base homeBase = (Base)minDist(myBases);
      if (homeBase != null) {
        float dist = distance(homeBase);
        if (dist <= 2) {
          // Deposit food at base
          giveFood(homeBase, carryingFood);
        } else if (dist < basePerception) {
          // Go towards base
          heading = towards(homeBase);
          tryToMoveForward();
        }
      }
    }
  }

  //
  // lookForEnemyBase
  // ================
  // > actively search for enemy base
  //
  void lookForEnemyBase() {
    Base enemyBase = (Base)oneOf(perceiveRobots(ennemy, BASE));
    if (enemyBase != null && brain[4].y == 0) {
      // Enemy base found!
      brain[0].x = enemyBase.pos.x;
      brain[0].y = enemyBase.pos.y;
      brain[4].y = 1; // Mark that we know enemy base
      brain[0].z = 0; // Info not yet transmitted
    }
  }

  //
  // transmitEnemyBaseIntel
  // ======================
  // > transmit enemy base position to our base
  //
  void transmitEnemyBaseIntel(Base base) {
    if (brain[4].y == 1) {
      float[] args = new float[3];
      args[0] = brain[0].x;
      args[1] = brain[0].y;
      args[2] = BASE;
      sendMessage(base, INFORM_ABOUT_TARGET, args);
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
    
    // If cargo is almost full, try to transfer to nearby explorer
    if (carryingFood > 150 && carryingFood < 200) 
    {
      Explorer nearbyExplorer = (Explorer)minDist(perceiveRobots(friend, EXPLORER));

      if(nearbyExplorer != null)
      {
        if(distance(nearbyExplorer) <= 2)
        {
          // Transfer half the food to the explorer
          float transferAmount = carryingFood / 2;
          giveFood(nearbyExplorer, transferAmount);
        }

        // Notify nearby explorers that harvester is full
        requestFoodTransfer();
      }
    }

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
  // requestFoodTransfer
  // ===================
  // > inform nearby explorers that cargo is full and request transfer
  //
  void requestFoodTransfer() {
    // Look for nearby friendly explorers
    ArrayList explorers = perceiveRobots(friend, EXPLORER);

    if (explorers != null) {
      for (int i = 0; i < explorers.size(); i++) {
        Explorer explorer = (Explorer)explorers.get(i);
        // Send message with current position and amount of food
        float[] args = new float[3];
        args[0] = pos.x;
        args[1] = pos.y;
        args[2] = carryingFood;
        sendMessage(explorer, RedTeam.HARVESTER_FULL, args);
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
//   2.y = (0 = no communicated target | 1 = has communicated target)
//   3.x / 3.y = position of communicated target from explorer
//   3.z = breed of communicated target
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
    // Handle messages from explorers (only when not busy)
    if (brain[4].x == 0 && brain[4].y == 0) {
      handleMessages();
    }
    
    // if no energy or no bullets, go back to base
    if ((energy < 500) || (bullets == 0)) {
      brain[4].x = 1;
      brain[2].y = 0; // Clear communicated target when going to base
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
    } else if (hasCommunicatedTarget()) {
      // Move towards communicated target from explorer
      moveTowardsCommunicatedTarget();
    } else {
      // else explore randomly
      randomMove(45);
    }
  }

  //
  // handleMessages
  // ==============
  // > handle messages received from explorers
  // > only accepts new targets when in search mode (not busy)
  //
  void handleMessages() {
    Message msg;
    // for all messages
    for (int i=0; i<messages.size(); i++) {
      msg = messages.get(i);
      if (msg.type == INFORM_ABOUT_TARGET) {
        // Store the communicated target position and breed
        brain[3].x = msg.args[0]; // x position
        brain[3].y = msg.args[1]; // y position
        brain[3].z = msg.args[2]; // breed
        brain[2].y = 1; // Mark that we have a communicated target
      }
    }
    // clear the message queue
    flushMessages();
  }

  //
  // hasCommunicatedTarget
  // =====================
  // > checks if a communicated target from explorer is available
  //
  // output
  // ------
  // > true if communicated target available / false if not
  //
  boolean hasCommunicatedTarget() {
    return (brain[2].y == 1);
  }

  //
  // moveTowardsCommunicatedTarget
  // ==============================
  // > move towards the target communicated by an explorer
  //
  void moveTowardsCommunicatedTarget() {
    // Get communicated target position
    PVector targetPos = new PVector(brain[3].x, brain[3].y);
    float distToTarget = distance(targetPos);
    
    // If we're close enough, clear the communicated target
    // (we'll rely on our own perception now)
    if (distToTarget < launcherPerception) {
      brain[2].y = 0; // Clear communicated target flag
      return;
    }
    
    // Move towards the communicated target
    heading = towards(targetPos);
    tryToMoveForward();
  }

  //
  // selectTargetWithPriority
  // ========================
  // > select target based on priority system:
  // > 1. Harvesters (economic targets)
  // > 2. Bases
  // > 3. Rocket Launchers (only if we can do significant damage)
  // > 4. Explorers (lowest priority)
  //
  void selectTargetWithPriority() {
    Robot bob = null;

    // Priority 1: Enemy harvesters (economic targets)
    bob = (Robot)minDist(perceiveRobots(ennemy, HARVESTER));
    
    // Priority 2: Enemy bases
    if(bob == null)
    {
      bob = (Robot)minDist(perceiveRobots(ennemy, BASE));
    }
    
    // Priority 3: Enemy rocket launchers
    if (bob == null) {
      Robot enemyLauncher = (Robot)minDist(perceiveRobots(ennemy, LAUNCHER));
      if (enemyLauncher != null) {
        // Only engage if we can make important damages
        if( bullets >= enemyLauncher.bullets / 2)
        {
          bob = enemyLauncher;
        }
        // Retreat
        else
        {
          brain[4].x = 1; // Go back to base
          brain[4].y = 0; // Clear target lock
          brain[2].y = 0; // Clear communicated target
          return;
        }
      }
    }
    
    // Priority 4: Enemy explorers not close to base (lowest priority)
    if (bob == null) {
      bob = (Robot)minDist(perceiveRobots(ennemy, EXPLORER));
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
      // Clear communicated target since we have a direct target now
      brain[2].y = 0;
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
    
    // Bullet travel time (use correct bullet speed from game parameters)
    float bulletTravelTime = distToTarget / bulletSpeed;
    
    // Check if target is moving or stationary
    // If speed is very low or zero, target is essentially stationary
    if (target.speed < 0.1) {
      // Target is stationary or barely moving - shoot directly at it
      return target.pos.copy();
    }
    
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
    
    // Calculate angle towards predicted position
    float angleToTarget = towards(predictedPos);
    
    // OPTIMIZED MOVEMENT with minimum safe distance
    float optimalDistance = launcherPerception * 0.7;  // Optimal shooting distance
    float minSafeDistance = 1.0;  // Minimum distance to avoid passing through
    
    if (distToTarget > optimalDistance) {
      // Too far - move closer aggressively
      heading = towards(targetPos);
      tryToMoveForward();
    } 
    else if (distToTarget < minSafeDistance) {
      // TOO CLOSE - RETREAT to safe distance
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
    
    // IMPROVED SHOOTING - only shoot if properly aimed
    if (distToTarget >= minSafeDistance) {
      // Check if no friendly robots are in the line of fire
      ArrayList friendsInCone = perceiveRobotsInCone(friend, angleToTarget);
      
      if (friendsInCone == null || friendsInCone.size() == 0) {
        // Set heading precisely to the predicted position
        heading = angleToTarget;
        
        // Add a small accuracy check - only shoot if facing roughly the right direction
        float headingDiff = abs(heading - angleToTarget);
        if (headingDiff < radians(10)) {  // Within 10 degrees
          launchBullet(heading);  // Use current heading, not recalculated angle
        }
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