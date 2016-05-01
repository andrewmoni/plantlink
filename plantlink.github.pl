#!/usr/bin/perl

 use strict;
 use JSON;
 use Data::Dumper;
 use DBI;
 require LWP::UserAgent;
 use Time::Local;

#----------------------------------------------
#main program options
#
 my $plantdebug = 0;              # set =1 to create debug file of Plantlink self plants
 my $measuredebug = 0;            # set =1 to create debug file of Plantlink plant readings
 my $usewunderground = 0;         # set =1 if want to get temperatures from Weather Underground
 my $wunderkey = "xxxxxxxxxxxxx"  # set to WU API key value supplied by Weather Underground
 my $conditionsdebug = 0;         # set =1 to create debug file when getting history from Weather Underground
 my $createcsv = 0;               # set =1 to create a .csv file of readings + corrections

#our $host = "raspberrypi";
our $host = "localhost";          # points to mySQL server machine

our $user = "xx";                 # xx is user name on $host
our $pass = "xxxxxxxx";           # xxxxxxxx is password for user $user on host $host

our $db ="mesowx";                # database for outdoor shade temperatures, keyed by dateTime, reading in outTemp
our $dbh = DBI->connect("DBI:mysql:$db:$host", $user, $pass) or die "Connection Error: $DBI::errstr\n";

our $readdb = "plantlink";        # database for Plantlink plants and plant readings (and corrections)
our $readdbh = DBI->connect("DBI:mysql:$readdb:$host", $user, $pass) or die "Cooection to readings error: $DBI::errstr\n";

 my $plantinfo;
 my $measurementinfo;

 my $plantname;

 my $conditions;

 my $i;
 my $count;
our @tem;
our $readingtemp;
our $correctiontemp;
our $epochstart;
our $epochend;

#----------------------------------------------

 my($year, $month, $day, $hour, $minute, $second) = localtime();
 $year += 1900;
 $month += 1; 

#
#--------------------------------------------------------------------

sub parsedate 
  { 
  my($s) = @_;

  if($s =~ m{^\s*(\d{1,2})\W*0*(\d{1,2})\W*0*(\d{1,4})\W*0*
                 (\d{0,2})\W*0*(\d{0,2})\W*0*(\d{0,2})}x) 
    {
    $year = $3;  $month = $2;   $day = $1;
    $hour = $4;  $minute = $5;  $second = $6;
    $hour |= 0;  $minute |= 0;  $second |= 0;  # defaults.
    $year = ($year<100 ? ($year<70 ? 2000+$year : 1900+$year) : $year);
    return timelocal($second,$minute,$hour,$day,$month-1,$year);  
    }
  return -1;
  }


#-------------------------------------------------------------------------------------------
# G E T   D A T E : Get date set to 7 days prior, or uncomment to key a start date
#-------------------------------------------------------------------------------------------

# print "Start date (dd-mm-yy): ";
# my $startdate = <STDIN>;
# $epochstart = parsedate($startdate);
# $epochend = $epochstart + 86400;
# if ($epochend > time()) {$epochend = time()};
 $epochstart = time() - (7 * 24 * 60 * 60);
 my ($second, $minute, $hour, $day, $month, $year, $wday, $yday, $isdst) = localtime($epochstart);
 $year += 1900;
 $month += 1; 

 $epochend = time();

 my $wuhistorydate = $year . sprintf("%02d",$month) . sprintf("%02d", $day);
 my $wuurl = 'http://api.wunderground.com/api/' . $wunderkey . '/history_' . $wuhistorydate . '/q/pws:ILIMASSO5.json';

 unlink("readings_" . $wuhistorydate . ".csv");

#------------------------------------------------------------------------------
# G E T     T E M P E R A T U R E S   F R O M   W U N D E R G R O U N D
#------------------------------------------------------------------------------
 if ($usewunderground)
 {
 my $ua = LWP::UserAgent->new;
 my $req = HTTP::Request->new(GET => $wuurl);
 $req->authorization_basic('xxxxxxxxxxxxxxxxxxxx','xxxxxxxxxxxx');   #Plantlink user name and password
 my $response = $ua->request($req);
 if ($response->is_success) 
  {
    $conditions = decode_json $response->decoded_content;
  }
 else 
  {
    print "Error: ",$response->status_line;
    exit;
  }

 if ($conditionsdebug)
  {
    open DUMPFILE, ">wuhistory.txt" or die "cannot open wu history response dump file"; 
    print DUMPFILE Dumper($conditions);
    close DUMPFILE;
  }

 my $temps = $conditions->{history}->{observations};

 if ($conditionsdebug)
 {
   open DUMPFILE, ">wutemps.txt" or die "cannot open wu history response observations dump file"; 
   print DUMPFILE Dumper($temps);
   close DUMPFILE;
 }

#-------------------------------------------------------------------
# BUILD HOURLY TEMPERATURES ARRAY
#-------------------------------------------------------------------
for my $keyvar (0..23) {@tem[$keyvar] = [0]};

foreach (@$temps)
 {
    my $myhour = $_->{date}->{hour};
    my $mytemp = $_->{tempm};
    push $tem[$myhour], $mytemp;
    if ($conditionsdebug)
    {
      print $myhour . "  " . $mytemp . "\n";
    }
 }

#print Dumper(@tem);

#--------------------------------
#calculate hourly average
#--------------------------------
for (my $keyvar = 0; $keyvar < @tem; $keyvar++)
 {
        if ($conditionsdebug) {print $keyvar . ":00 - ";}
   my $hrtotal = 0;
   for (my $j = 1; $j < @{ $tem[$keyvar] }; $j++)
   {
      $hrtotal = $hrtotal + $tem[$keyvar][$j];
        if ($conditionsdebug) {print ($tem[$keyvar][$j]);}
        if ($conditionsdebug) {print ("  ");}
   }
   if (@{ $tem[$keyvar] } > 1)
     {   
        $tem[$keyvar][0] = $hrtotal / (@{ $tem[$keyvar] } - 1);
     }
   else
     {
        $tem[$keyvar][0] = $hrtotal; 
     }
        if ($conditionsdebug) {print ($tem[$keyvar][0]);}  
        if ($conditionsdebug) {print "\n";}
  }

 } #end of wunderground temperatures

#----------------------------------------------------------------------
#G E T    M Y    P L A N T S    F R O M    P L A N T L I N K
#----------------------------------------------------------------------

 my $getplantsurl = 'https://dashboard.myplantlink.com/api/v1/plants';

 my $ua = LWP::UserAgent->new;
 my $req = HTTP::Request->new(GET => $getplantsurl);
 $req->authorization_basic('xxxxxxxxxxxxxxxxxxxxx','xxxxxxxxxxxxxxxxxxx');   #Plantlink user name and password
 my $response = $ua->request($req);
 if ($response->is_success) 
  {
    $plantinfo = decode_json $response->decoded_content;
  }
 else 
  {
    print "Error getting list of plants from Plantlink: ",$response->status_line;
    exit;
  }

 if ($plantdebug)
 {
  open DUMPFILE, ">plantinfo.txt" or die "cannot open plants info debug txt file"; 
  print DUMPFILE Dumper($plantinfo);
  close DUMPFILE;
 }

 our $query = "select * from plants where plantID = ?";
 our $plantssqlQuery = $readdbh->prepare('select * from plants where plantID = ? ') or die;
 our $plantcreate = $readdbh->prepare(' insert into plants (plantID, name, lastread) values ( ?, ?, ? )');
 our $readingcreate = $readdbh->prepare(' insert into readings (plantkey, reading_time, raw_reading, day_time, temperature, corr_temp, moisture, corrected_moisture, status) values (?, ?, ?, ?, ?, ?, ?, ?, ?)');
 our $getlastreading = $readdbh->prepare(' select max(reading_time) from readings where plantkey = ?') or die;

 our $rv;
 our @row;

#----------------------------------------------------------------------------
# G E T    R E A D I N G S    F O R    O N E    P L A N T
#----------------------------------------------------------------------------

 foreach (@$plantinfo)
 {
   my $plantid = $_->{key};   
   $rv = $plantssqlQuery->execute($plantid);
   @row = $plantssqlQuery->fetchrow_array;
   
   if ( $plantssqlQuery->rows )                               #see if the plant already exists in my database
     {
     print "database record for " . $_->{name} . $plantid . " read OK" . "  ";
     }
   else
     {
     print "creating database plant record for ID: " . $_->{key} . "  " . $_->{name} . "  ";
     $rv = $plantcreate->execute($_->{key}, $_->{name}, 0000000000);
     }
#------------------------------------------------------------
#update existing or newly created plant record with latest info - except last reading time
#------------------------------------------------------------

   my $temp = "$_->{status}";
   my $shortstat = substr($temp,0,3);
   my $var1 = $_->{last_watered_datetime};
   my $var2 = $_->{default_lower_moisture_threshold};
   my $var3 = $_->{default_upper_moisture_threshold};
   my $var4 = $_->{user_lower};
   my $var5 = $_->{user_upper};
   my $var6 = $_->{upper_moisture_threshold};
   my $var7 = $_->{lower_moisture_threshold};
   my $varid = $_->{key};
print $temp . "\n";

   my $plantupdatestmt = "UPDATE plants SET 
          lastwatered = ?, 
          default_lower = ?, 
          default_upper = ?,
          user_lower = ?,
          user_upper = ?,
          upper_threshold = ?,
          lower_threshold = ?,
          status = ?
          WHERE plantID = ?";

   $readdbh->do($plantupdatestmt, undef, $var1, $var2, $var3, $var4, $var5, $var6, $var7, $temp, $varid);

#                $plantinfo->[$_]->{default_lower_moisture_threshold},
#                $plantinfo->[$_]->{default_upper_moisture_threshold},
#                $plantinfo->[$_]->{user_lower_moisture_threshold},
#                $plantinfo->[$_]->{user_upper_moisture_threshold},
#                $plantinfo->[$_]->{upper_moisture_threshold},
#                $plantinfo->[$_]->{lower_moisture_threshold},
#                $temp,
#                $plantinfo->[$_]->{key});

  my $savedate = $epochstart;

  if ($row[2] == 0)                                     #see if there is a last reading time in plant table
     {                                                  #if there is request more from after it else use keyed date
     $rv = $getlastreading->execute($_->{key});
     @row = $getlastreading->fetchrow_array;
     if ($getlastreading->rows)
       {
       $epochstart = $row[1] + 1;
       }
     else
       {
       $epochstart = time() - (7 * 24 * 60 * 60);
       }
     }
  else
     {
     $epochstart = $row[2] + 1;
     }
   
   my $plantname = $_->{name};
   print sprintf ("%-25s", $plantname);
   print scalar localtime($_->{last_measurements}->[0]->{updated}), "\n";
   if ($epochend >= $_->{last_measurements}->[0]->{updated}) 
     {
       $epochend = $_->{last_measurements}->[0]->{updated} + 60;
     }
   my $getreadingsurl = 'https://dashboard.myplantlink.com/api/v1/plants/' . $_->{key} . '/measurements?start_datetime=' . $epochstart . '&limit=1000';
 #  print "Plantlink reading request: ", $getreadingsurl, "\n";

   $epochstart = $savedate;
 
   my $ua = LWP::UserAgent->new;
   my $req = HTTP::Request->new(GET => $getreadingsurl);
   $req->authorization_basic('xxxxxxxxxxxxxxxxxxxx','xxxxxxxxxxxxxx');     #Plantlink user name and password
   my $response = $ua->request($req);

   if ($response->is_success) 
     {
        $measurementinfo = decode_json $response->decoded_content;
     }
   else 
     {
        print "Error: ",$response->status_line;
        exit;
     }
 
 if ($measuredebug)
   {
     open DUMPFILE, ">>measurementinfo.txt" or die "cannot open measurements txt file"; 
     print DUMPFILE Dumper($measurementinfo);
     close DUMPFILE;
   }
#------------------------------------------------------------
# O U T P U T     C S V   F O R   O N E   P L A N T
#------------------------------------------------------------
 if ($createcsv)
 {
 open OUTFILE, ">>readings_" . $wuhistorydate . ".csv" or die "cannot open readings csv file";
 }
 my $plantname = $_->{name};

 $i = 0;
 while ($measurementinfo->[$i]->{created} > 0)
  {
    my $moisturelevel = $measurementinfo->[$i]->{moisture};
    my $rawmoisture = oct($measurementinfo->[$i]->{moisture_raw_reading});
    my $percentadjust = 0;

    if ($createcsv)
    {
      print OUTFILE $plantname . "," . $measurementinfo->[$i]->{created} . "," . $rawmoisture . ",";
      print OUTFILE scalar localtime($measurementinfo->[$i]->{created});
    }

    my $time = $measurementinfo->[$i]->{created};
    my ($sec, $min, $hour, $day, $month, $year) = (localtime($time))[0,1,2,3,4,5];
    if ($usewunderground)
    {
    $readingtemp = ($tem[$hour][0]);
    my $correcthour = (($hour > 1) ? $hour - 2 : 0);
    $correctiontemp = ($tem[$correcthour][0]);
    }
    else
    {
      our $corrtempquery = "select dateTime, outTemp from raw where (dateTime < ($time - 7200)) and (outTemp > 0) order by dateTime DESC limit 1";
      our $corrtempsqlQuery = $dbh->prepare($corrtempquery) or die;
      our $corrtemprv = $corrtempsqlQuery->execute or die;
      our @corrtemprow;
      my $foundtemp = 0;
      while (@corrtemprow = $corrtempsqlQuery->fetchrow_array())
        {
           $correctiontemp = $corrtemprow[1];
           if ($correctiontemp)
             {
              $foundtemp++;
#              print "readingtime: ", $time, " corr time: ", $corrtemprow[0], " temp: ", $correctiontemp, "\n";
              last;
             }
        }

      if ($foundtemp = 0)
        {
        print "no correction temp for: ", $time, "\n";
        }

      our $tempquery = "select dateTime, outTemp from raw where (dateTime < ($time + 300)) and (outTemp > 0) order by dateTime DESC limit 1";
      our $tempsqlQuery = $dbh->prepare($tempquery) or die;
      our $temprv = $tempsqlQuery->execute or die;
      my $foundtemp = 0;
      while (our @temprow = $tempsqlQuery->fetchrow_array())
        {
           $readingtemp = $temprow[1];
           if ($readingtemp)
             {
              $foundtemp++;
#              print "readingtime: ", $time, " temp: ", $readingtemp, " corr time: ", $corrtemprow[0], " temp: ", $correctiontemp, "\n";
              last;
             }
        }

      if ($foundtemp = 0)
        {
        print "no temp for: ", $time, "\n";
        }


    }
    
    my $prettytime = sprintf("%02d", $day) . " " . sprintf("%02d", $hour) .  ":" . sprintf("%02d", $min);

    if ($createcsv)
    {
       print OUTFILE ",", $prettytime, ",";
       print OUTFILE sprintf("%5.2f", $readingtemp), ",", "   ", sprintf("%5.2f", $correctiontemp);
       print OUTFILE ",", "    ", sprintf("%5.4f", $moisturelevel * 100), ",", "   ";
    }

#--------------------------------------------------------
#do temperature related correction - 1.x% per degree where x=int(temp/10)
#--------------------------------------------------------
    if (($measurementinfo->[$i]->{created} < $var1) || ($measurementinfo->[$i]->{created} > ($var1 + 10800)))
    {
      $percentadjust = 1.7 * ($correctiontemp - 20);
    }
    else
    {
      $percentadjust = 0;
    }
    
    $moisturelevel = $moisturelevel * 100;
    my $corrected_moisture = $moisturelevel - (($moisturelevel * $percentadjust) / 100);

    if ($createcsv)
    {
    print OUTFILE sprintf("%5.4f", $corrected_moisture); 
    print OUTFILE "\n";
    }

#--------------------------------------------------------
#insert reading into database
#--------------------------------------------------------
    $readingcreate->execute($_->{key}, $measurementinfo->[$i]->{created}, $rawmoisture, $prettytime, $readingtemp, $correctiontemp, $moisturelevel, $corrected_moisture, $shortstat);

    $i ++;
  }

  $rv = $getlastreading->execute($_->{key});
  @row = $getlastreading->fetchrow_array;
  $readdbh->do("update plants set lastread = $row[0] where plantID = $_->{key}");
 
  if($createcsv)
  {
     close OUTFILE;
  }
}
#-----------------------------------------------------------------------
my $deletedate = $row[0] - 864000;
print "delete if 10 days before: " . $row[0] . " at " . $deletedate . "\n";

$readdbh->do("delete from readings where reading_time < $deletedate");
END:

