//Austin Martyn's simple rocket landing script.

//Settings
SET coefDragSArea TO 20.   //The Coefficient of Drag * Exposed Surface Area of the rocket when pointing retrograde. Value is in Meters Squared.
SET timeStepSize TO .5.    //Determines how accurate the suicide burn simulation is. Smaller Number = More Accurate but Slower Simulation. Value is in Seconds.
SET safetyFactor TO 1.4.   //How much wiggle room there is to account for error in the predictions. 
SET burnCutoffSpeed TO 50. //Speed at which the rocket will try to orient mostly vertical. This is so the rocket does not over/undershoot landings. Value is in Meters per Second.
SET maxLandingSpeed TO 5.  //The speed the rocket will try be when it lands. Value is in Meters per Second.

clearscreen.
print "Initializing...".

//Get the rocket into a known state
SAS OFF.
RCS ON.
GEAR OFF.
LOCK THROTTLE TO 0.
BRAKES ON.

//delare and initialize some variables
LOCK thrust TO SHIP:AVAILABLETHRUSTAT(body:atm:ALTITUDEPRESSURE(ALTITUDE)).
LOCK betterAltitude TO MIN(ALT:RADAR,SHIP:ALTITUDE).
LOCK speed TO SQRT(VERTICALSPEED^2 + GROUNDSPEED^2).
SET gravAccel TO (Constant:G * Body:MASS) / (Body:RADIUS*Body:RADIUS). //acceleration due to gravity.
SET burnAltitude TO 0.
SET tmpAltitude TO ALTITUDE.
SET runmode TO 1.

//Get all usable engines
LIST ENGINES IN eng.
SET tmp TO 0.
UNTIL tmp = 1 {
	LOCAL i is 0.
	SET i TO 0.
	FROM {local i is 0.} UNTIL i = eng:length STEP {SET i TO i+1.} DO {
		
		IF eng[i]:STAGE > STAGE:NUMBER OR eng[i]:AVAILABLETHRUST < .1 {
			eng:REMOVE(i).
			SET i TO 0.
			BREAK.
		} ELSE IF i = eng:length - 1{
			SET tmp TO 1.
		}		
	}
}

until runmode = 0 {
	
	clearscreen.
	PRINT "Runmode: " + runmode.
	
	IF runmode = 1 { //Wait until the current altitude reaches the predicted suicide burn altitude
		PRINT "Waiting For Optimal Time To Burn...".
		PRINT "Burn Altitude:       " + burnAltitude.
		
		LOCK STEERING TO SRFRETROGRADE.
		
		SET deltaAltitude TO tmpAltitude - ALTITUDE.
		IF (ALTITUDE - deltaAltitude < burnAltitude) {
			LOCK THROTTLE TO 1.
			GEAR ON.
			SET runmode TO 2.
		} ELSE {
			SET tmpAltitude TO ALTITUDE. 
			SET burnAltitude TO getBurnAltitude().
		}				
	}
	ELSE IF runmode = 2 { //Do the suicide burn until the rockets speed is less than the specified cutoff speed.
		PRINT "Performing Suicide Burn...".
		
		IF (speed < burnCutoffSpeed) {
			SET runmode TO 3.
		} 
	}
	ELSE IF runmode = 3 { //Point the rocket mostly vertical and make a soft touchdown.
		PRINT "Landing...".
		
		LOCK STEERING TO UP:Vector + (SRFRETROGRADE:Vector * .3).
		
		IF (-VERTICALSPEED > maxLandingSpeed) {		
			SET neededAcceleration TO (maxLandingSpeed + speed + gravAccel).
			SET requiredThrottle TO neededAcceleration / (thrust / SHIP:MASS).
			SET THROTTLE TO MAX(0, MIN(1.0, requiredThrottle)).
		} ELSE {
			SET THROTTLE TO MAX(0, MIN(1.0 , (SHIP:MASS * (gravAccel - 1)) / thrust)).
		}
		
		IF (-VERTICALSPEED < 1) {
			SET runmode TO 0.
		}
	}
	ELSE {
		PRINT "INVALID RUNMODE! Terminating Program...".
		SET runmode TO 0.
	}
	
	WAIT .1.
}

LOCK THROTTLE TO 0.

//Get the minimum starting altitude needed for a successful suicide burn.
//Uses simulation to determine the value.
//Assumes rocket is always burning retrograde.  
FUNCTION getBurnAltitude {

	//Get the engine's current ISP and fuel consumption rate. 
	SET sumISP TO 0.
	FOR e IN eng {
		SET sumISP TO sumISP + e:ISPAT(body:atm:ALTITUDEPRESSURE(ALTITUDE)).
	}
	SET avgISP TO sumISP / eng:length.
	SET fuelFlowRate TO thrust/(avgISP*9.8).
	
	//Simulate to find what altitude the rocket will end up at if it burned right now.
	SET altitudeThisStep TO ALTITUDE.
	SET vertVelThisStep TO -VERTICALSPEED.
	SET grndVelThisStep TO GROUNDSPEED.
	SET massBeginThisStep TO SHIP:MASS.	
	UNTIL vertVelThisStep < 0 {
		
		//How much acceleration due to engines and drag will be applied in the vertical / horizontal directions.
		SET vertComponent TO vertVelThisStep / SQRT(vertVelThisStep^2 + grndVelThisStep^2).
		SET lateralComponent TO grndVelThisStep / SQRT(vertVelThisStep^2 + grndVelThisStep^2).
		
		//Use the rocket equation to find the average acceleration from the engines.
		SET massEndThisStep TO massBeginThisStep - (timeStepSize * fuelFlowRate).
		SET engineDeltavThisStep TO avgISP * 9.8 * LN(massBeginThisStep / massEndThisStep).
		SET avgEngineAccelThisStep TO (engineDeltavThisStep / timeStepSize) * vertComponent.
		
		SET avgMassThisStep TO (massBeginThisStep + massEndThisStep) / 2.
		
		//Use the drag equation to find the average acceleration from drag.
		SET airDensityThisStep TO 1.225 * body:atm:ALTITUDEPRESSURE(altitudeThisStep).
		SET dynPressureThisStep TO .5 * airDensityThisStep *(vertVelThisStep^2 + grndVelThisStep^2). 
		SET dragThisStep TO (dynPressureThisStep * coefDragSArea) / 1000.
		SET avgDragAccelThisStep TO (dragThisStep / avgMassThisStep) * vertComponent.
		
		//Find the average accelerations in both directions.
		SET vertAccelThisStep TO gravAccel - avgEngineAccelThisStep - avgDragAccelThisStep. //Average vertical acceleration.
		SET grndAccelThisStep TO lateralComponent * ((engineDeltavThisStep / timeStepSize) + (avgDragAccelThisStep * timeStepSize)).
		
		//Compute future velocities and set stuff up for the next step.
		SET tmpVel TO vertVelThisStep.
		SET vertVelThisStep TO vertVelThisStep + vertAccelThisStep * timeStepSize.
		SET vertDistThisStep TO .5 *(tmpVel + vertVelThisStep) * timeStepSize.
		SET altitudeThisStep TO altitudeThisStep - vertDistThisStep.
		SET grndVelThisStep TO grndVelThisStep - grndAccelThisStep.
		SET massBeginThisStep TO massEndThisStep.

	}
	
	SET distanceNoVelocity TO (ALTITUDE - altitudeThisStep) * safetyFactor.
	RETURN (ALTITUDE - betterAltitude) + distanceNoVelocity.
}