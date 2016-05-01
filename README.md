# plantlink
Read plants and readings from plantlink and create .csv file or insert into mysql database with temperature correction

There are several options and flags which can be set at the start of the program to make life easier.

The program is intended to correct the readings obtained from Plantlink soil moisture sensors, which are affected by external sun temperatures.  The program accesses either Weather Underground or a local mysql database to obtain the external shade temperature at the time of the reading.  The Link moisture is the adjusted as reading - reading * 1.7 * (temperature -20)/100.  Temperature is taken from, two hours before reading time to compensate for soil temperature.  If watering is detected no correction is made for 2 hours.  Assumes that the link is in a shaded position or protected by a sunshade of some kind!!


