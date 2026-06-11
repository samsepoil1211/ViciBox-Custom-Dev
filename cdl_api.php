<?php
# cdl_api.php v3
# Column fix: this ViciBox install uses 'auto_dial_level' not 'dial_level'
# Connects to master DB directly via astguiclient.conf credentials

header("Content-Type: application/json");
header("Cache-Control: no-cache, no-store");

$conf = '/etc/astguiclient.conf';
$db_server = 'localhost'; $db_name = 'asterisk';
$db_user = 'cron'; $db_pass = '1234'; $db_port = 3306;
if (is_readable($conf)) {
    foreach (file($conf) as $line) {
        if (preg_match('/^VARDB_server\s*=>\s*(\S+)/',   $line, $m)) $db_server = $m[1];
        if (preg_match('/^VARDB_database\s*=>\s*(\S+)/', $line, $m)) $db_name   = $m[1];
        if (preg_match('/^VARDB_user\s*=>\s*(\S+)/',     $line, $m)) $db_user   = $m[1];
        if (preg_match('/^VARDB_pass\s*=>\s*(\S+)/',     $line, $m)) $db_pass   = $m[1];
        if (preg_match('/^VARDB_port\s*=>\s*(\S+)/',     $line, $m)) $db_port   = (int)$m[1];
    }
}
$mlink = @mysqli_connect($db_server, $db_user, $db_pass, $db_name, $db_port);
if (!$mlink) {
    echo json_encode(array("ok"=>false,"err"=>"db_connect_failed","detail"=>mysqli_connect_error()));
    exit;
}

function cdl_esc($l,$s){ return mysqli_real_escape_string($l,(string)$s); }
function cdl_q($l,$s){ return mysqli_query($l,$s); }
function cdl_row($l,$s){ return mysqli_fetch_row(mysqli_query($l,$s)); }
function cdl_assoc($l,$s){ return mysqli_fetch_assoc(mysqli_query($l,$s)); }

$cdl_u   = isset($_GET["cdl_u"])        ? preg_replace("/[^-_0-9a-zA-Z]/u","", $_GET["cdl_u"])        : "";
$cdl_act = isset($_GET["cdl_action"])   ? preg_replace("/[^a-z]/",          "", $_GET["cdl_action"])   : "";
$cdl_cid = isset($_GET["cdl_campaign"]) ? preg_replace("/[^-_0-9a-zA-Z]/",  "", $_GET["cdl_campaign"]) : "";

if (strlen($cdl_u) < 1 && isset($_SERVER["PHP_AUTH_USER"]))
    { $cdl_u = preg_replace("/[^-_0-9a-zA-Z]/u","", $_SERVER["PHP_AUTH_USER"]); }

if (strlen($cdl_u) < 1)
    { echo json_encode(array("ok"=>false,"err"=>"no_user")); mysqli_close($mlink); exit; }

$uE = cdl_esc($mlink, $cdl_u);
$pr = cdl_row($mlink, "SELECT modify_campaigns,user_level,user_group,active FROM vicidial_users WHERE user='$uE' LIMIT 1;");

if (!$pr || $pr[3] !== "Y")
    { echo json_encode(array("ok"=>false,"err"=>"auth_failed","user"=>$cdl_u)); mysqli_close($mlink); exit; }

$can_write  = ($pr[0]==="1" && (int)$pr[1] > 6);
$ugE        = cdl_esc($mlink, $pr[2]);
$gr         = cdl_row($mlink, "SELECT allowed_campaigns FROM vicidial_user_groups WHERE user_group='$ugE' LIMIT 1;");
$allowedSQL = "";
if (isset($gr[0]) && !preg_match("/ALL-/", $gr[0])) {
    $raw = preg_replace("/ -/", "", $gr[0]);
    $raw = preg_replace("/ /", "','", $raw);
    $allowedSQL = "and campaign_id IN('$raw')";
}

$cidE = cdl_esc($mlink, $cdl_cid);
$resp = array("ok"=>false);

if ($cdl_act === "campaigns") {
    $list = array();
    # auto_dial_level is the correct column name on this ViciBox install
    $rs = cdl_q($mlink, "SELECT campaign_id, campaign_name, auto_dial_level AS dial_level, dial_method FROM vicidial_campaigns WHERE 1=1 $allowedSQL ORDER BY campaign_id;");
    while ($row = mysqli_fetch_assoc($rs)) { $list[] = $row; }
    $resp = array("ok"=>true, "can_write"=>$can_write, "campaigns"=>$list, "count"=>count($list));
}
elseif ($cdl_act === "get" && strlen($cidE) > 0) {
    $g = cdl_assoc($mlink, "SELECT auto_dial_level AS dial_level, dial_method, campaign_name, active FROM vicidial_campaigns WHERE campaign_id='$cidE' $allowedSQL LIMIT 1;");
    if ($g) $resp = array("ok"=>true, "dial_level"=>$g["dial_level"], "dial_method"=>$g["dial_method"], "campaign_name"=>$g["campaign_name"], "active"=>$g["active"]);
    else    $resp = array("ok"=>false, "err"=>"campaign_not_found", "cid"=>$cidE);
}
elseif (($cdl_act==="set" || $cdl_act==="reset") && $can_write && strlen($cidE) > 0) {
    $cc = cdl_row($mlink, "SELECT count(*) FROM vicidial_campaigns WHERE campaign_id='$cidE' $allowedSQL;");
    if ((int)$cc[0] > 0) {
        if ($cdl_act === "reset") { $dl = "1.0"; }
        else {
            $dl = (float)(isset($_GET["cdl_dial_level"]) ? $_GET["cdl_dial_level"] : 1);
            if ($dl < 1) $dl = 1; if ($dl > 20) $dl = 20;
            $dl = number_format($dl, 1, ".", "");
        }
        cdl_q($mlink, "UPDATE vicidial_campaigns SET auto_dial_level='$dl' WHERE campaign_id='$cidE'");
        $ipE = cdl_esc($mlink, isset($_SERVER["REMOTE_ADDR"]) ? $_SERVER["REMOTE_ADDR"] : "");
        @cdl_q($mlink, "INSERT INTO vicidial_admin_log (event_date,user,ip_address,event_section,event_type,record_id,event_code,event_sql,event_notes) VALUES (NOW(),'$uE','$ipE','CAMPAIGNS','MODIFY','$cidE','MODIFY DIAL_LEVEL','UPDATE vicidial_campaigns SET auto_dial_level=$dl','auto_dial_level $cdl_act via realtime panel')");
        $resp = array("ok"=>true, "dial_level"=>$dl);
    } else { $resp = array("ok"=>false,"err"=>"campaign_not_found"); }
}
elseif (!$can_write && ($cdl_act==="set"||$cdl_act==="reset"))
    { $resp = array("ok"=>false,"err"=>"no_modify_campaigns_permission"); }

mysqli_close($mlink);
echo json_encode($resp);
?>
