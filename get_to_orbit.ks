//Austin Martyn's simple rocket launch script.

//settings
SET minApoapsis TO 150000.  //The desired apoapsis altitude. Value is in Meters.
SET minPeriapsis TO 130000. //The desired periapsis altitude. Value is in Meters.
SET beginTurnAlt TO 25000.	//Altitude where 'gravity turn' starts. (Where thick atmosphere ends). Value is in Meters.
SET desiredHeading TO 90.   //Compass heading rocket will try to be aligned with. Value is in Degrees.

SET reusableStages TO lexicon().
//Add whatever stages are reusable to the lexicon. Format is (Stage Number, Fuel Level To Stage).
reusableStages:add(2,400). //small launcher



clearscreen.
print "Initializing...".

//Get the rocket into a known state
SAS OFF.
RCS OFF.
LOCK STEERING TO UP.
LOCK THROTTLE TO 0.

//delare and initialize some variables
SET MAXIMUMFLOAT TO 3.402823e38.
LOCK distFromCenter TO Body:RADIUS + ALTITUDE. //distance from the center of the planet
LOCK gravAccel TO (Constant:G * Body:MASS) / (distFromCenter)^2. //acceleration due to gravity.
LOCK thrust TO SHIP:AVAILABLETHRUSTAT(body:atm:ALTITUDEPRESSURE(ALTITUDE)).
LOCK LF TO Stage:LiquidFuel.
LOCK LH2 TO Stage:LqdHydrogen.
LOCK SF TO Stage:SolidFuel.
SET prevLF TO MAXIMUMFLOAT.
SET prevLH2 TO MAXIMUMFLOAT.
SET prevSF TO MAXIMUMFLOAT.
SET atmosToApoapsisRatio TO beginTurnAlt / minApoapsis.
LOCK gravityTurnCurve TO (1 + atmosToApoapsisRatio) * (SHIP:APOAPSIS / minApoapsis)  - atmosToApoapsisRatio - .05. //The pitch angle the rocket will try to follow depending on altitude.

SET runmode TO 1.

UNTIL runmode = 0 {
	
	CLEARSCREEN.
	PRINT "Runmode: " + runmode.	
	
	IF runmode = 1 { //get the ship above the thick part of the atmosphere
		PRINT "Attempting To Gain Altitude...".
		LOCK STEERING TO HEADING(desiredHeading,90). //straight up
		LOCK THROTTLE TO 1.
		IF ALTITUDE > beginTurnAlt {
			SET runmode TO 2.
		}
	}
	ELSE IF runmode = 2 { //burn while performing a "gravity turn" until Apoapsis reaches minApoapsis
		PRINT "Raising Apoapsis...".
		LOCK STEERING TO HEADING(desiredHeading,90 - 90 * gravityTurnCurve).
		IF SHIP:APOAPSIS > minApoapsis {
			SET runmode TO 3.
		}
		ELSE IF ETA:APOAPSIS > ETA:PERIAPSIS { //The rocket was not able to get the Apoapsis up to minApoapsis in time
			SET runmode TO 20.
		}
	}
	ELSE IF runmode = 3 { //burn horizontal until Periapsis reaches minPeriapsis or until Apoapsis is reached.
		PRINT "Raising Periapsis...".
		
		LOCK STEERING TO HEADING(desiredHeading,0). 
		IF SHIP:PERIAPSIS > minPeriapsis {
			SET runmode TO 0.
		} ELSE IF ETA:APOAPSIS > ETA:PERIAPSIS {
			SET runmode TO 4.
		}
	}
	ELSE IF runmode = 4 { //Burn horizontal until Periapsis reaches minPeriapsis. Try to stay on the Apoapsis durring the burn.
		PRINT "Raising Periapsis. Staying on Apoapsis...".
		
		SET correction TO MAX(-5, MIN(5, 1 * (-VERTICALSPEED))).
		SET centripetalAcceleration TO VELOCITY:ORBIT:MAG^2 / distFromCenter.
		SET angleAboveHorizontal TO ARCSIN((gravAccel - centripetalAcceleration) / (thrust / SHIP:MASS)) + correction.
		SET angleAboveHorizontal TO MAX(0, MIN(90, angleAboveHorizontal)).
		
		LOCK STEERING TO HEADING(desiredHeading, angleAboveHorizontal). 
		IF SHIP:PERIAPSIS > minPeriapsis {
			SET runmode TO 0.
		}
	}
	ELSE IF runmode = 20 { //make a last ditch attempt to bring the Apoapsis to minApoapsis
		PRINT "Making a Last Ditch Effort to Raise the Apoapsis...".
		LOCK STEERING TO HEADING(desiredHeading,90). //straight up
		IF SHIP:APOAPSIS > minApoapsis {
			SET runmode TO 3.
		}
	}	
	ELSE {
		PRINT "INVALID RUNMODE! Terminating Program...".
		SET runmode TO 0.
	}

	//Staging code
	IF (shouldStage()) {
		PRINT "Staging...".
		
		LOCK THROTTLE TO 0.
		STAGE.
		LOCK THROTTLE TO 0.3.
		UNTIL Stage:READY {
			WAIT .1.
		}
		WAIT 1.
		LOCK THROTTLE TO 1.
	}	
	
	SET prevLF TO LF.
	SET prevLH2 TO LH2.
	SET prevSF TO SF.
	
	PRINT "Apoapsis: " + ROUND(SHIP:APOAPSIS) + "m".
	PRINT "Periapsis: " + ROUND(SHIP:PERIAPSIS) + "m".
	WAIT .1.
}

LOCK THROTTLE TO 0.

//Returns true if fuel is not being used (burnout), or if there is less fuel in this stage than is specified in reusableStages.
FUNCTION shouldStage {
	IF (reusableStages:HASKEY(STAGE:NUMBER)) {
		RETURN LF < reusableStages[STAGE:NUMBER] AND LH2 < reusableStages[STAGE:NUMBER].
	}
	RETURN (prevLF - LF < .01) AND (prevLH2 - LH2 < .01) AND (prevSF - SF < .01).
}