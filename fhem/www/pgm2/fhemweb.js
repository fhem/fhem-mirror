"use strict";
var FW_version={};
FW_version["fhemweb.js"] = "$Id$";

var FW_serverGenerated;
var FW_jsLog;
var FW_serverFirstMsg = (new Date()).getTime()/1000;
var FW_serverLastMsg = FW_serverFirstMsg;
var FW_isIE = (navigator.appVersion.indexOf("MSIE") > 0);
var FW_isiOS = navigator.userAgent.match(/(iPad|iPhone|iPod)/) ||
               (navigator.platform === 'MacIntel' && 
                navigator.maxTouchPoints > 1); /* iPad OS 13+ */
var FW_scripts = {}, FW_links = {};
var FW_docReady = false, FW_longpollType, FW_csrfToken, FW_csrfOk=true;
var FW_root = "/fhem";  // root
var FW_availableJs={};
var FW_urlParams={};
var embedLoadRetry = 100;
var FW_os = "unknown";

if(FW_isiOS) { FW_os = "iOS";
} else if(navigator.userAgent.indexOf("Android") >= 0) { FW_os = "android";
} else if(navigator.userAgent.indexOf("OS X")    >= 0) { FW_os = "osx";
} else if(navigator.userAgent.indexOf("Windows") >= 0) { FW_os = "windows";
} else if(navigator.userAgent.indexOf("Linux")   >= 0) { FW_os = "linux";
}

// createFn returns an HTML Element, which may contain 
// - setValueFn, which is called when data via longpoll arrives
// - activateFn, which is called after the HTML element is part of the DOM.
var FW_widgets = {
  select:            { createFn:FW_createSelect    },
  selectnumbers:     { createFn:FW_createSelectNumbers, },
  slider:            { createFn:FW_createSlider    },
  time:              { createFn:FW_createTime      },
  noArg:             { createFn:FW_createNoArg     },
  multiple:          { createFn:FW_createMultiple  },
  "multiple-strict": { createFn:FW_createMultiple, second:true  },
  textField:         { createFn:FW_createTextField },
  textFieldNL:       { createFn:FW_createTextField, second:true },
  "textField-long":  { createFn:FW_createTextField, second:true },
  "textFieldNL-long":{ createFn:FW_createTextField, second:true },
  bitfield:          { createFn:FW_createBitfield  },
  widgetList:        { createFn:FW_createWidgetList },
};

window.onbeforeunload = function(e)
{ 
  FW_leaving = 1;
  return undefined;
}

window.onerror = function(errMsg, url, lineno)
{
  url = url.replace(/.*\//,'');
  if($("body").attr("data-confirmJSError") != 0)
    FW_okDialog(url+" line "+lineno+":<br>"+errMsg);
}


function
FW_replaceWidgets(parent)
{
  parent.find("div.fhemWidget").each(function() {
    var dev=$(this).attr("dev");
    var cmd=$(this).attr("cmd");
    var rd=$(this).attr("reading");
    var params = cmd.split(" ");
    var type=$(this).attr("type");
    if(type == undefined)
      type = "set";
    FW_replaceWidget(this, dev, $(this).attr("arg").split(","),
      $(this).attr("current"), rd, params[0], params.slice(1),
      function(arg) {
        FW_cmd(FW_root+"?cmd="+type+" "+dev+
                (params[0]=="state" ? "":" "+params[0])+" "+arg+"&XHR=1");
      });
  });
}

function
FW_jqueryReadyFn()
{
  if(FW_docReady)       // loading fhemweb.js twice is hard to debug
    return;
  FW_docReady = true;

  FW_serverGenerated = $("body").attr("generated");
  FW_jsLog = $("body").attr("data-jsLog");
  FW_longpollType = $("body").attr("longpoll");

  var ajs = $("body").attr("data-availableJs");
  if(ajs) {
    ajs = ajs.split(",");
    for(var i1=0; i1<ajs.length; i1++)
      FW_availableJs[ajs[i1]] = 1;
  }

  if(FW_longpollType != "0")
    setTimeout("FW_longpoll()", 100);
  FW_csrfToken = $("body").attr('fwcsrf');

  $("a").each(function() { FW_replaceLink(this); })
  $("head script").each(function() {
    var sname = $(this).attr("src"),
        p = FW_scripts[sname];
    if(!p) {
      FW_scripts[sname] = { loaded:true };
      return;
    }
    FW_scripts[sname].loaded = true;
    if(p.callbacks && !p.called) {
      p.called = true;  // Avoid endless loop
      for(var i1=0; i1< p.callbacks.length; i1++)
        if(p.callbacks[i1]) // pushing undefined callbacks on the stack is ok
          p.callbacks[i1]();
      delete(p.callbacks);
    }

  });
  $("head link").each(function() { FW_links[$(this).attr("href")] = 1 });

  $("div.makeSelect select").each(function() {
    FW_detailSelect(this);
    $(this).change(FW_detailSelect);
  });


  // Activate the widgets
  var r = $("head").attr("root");
  if(r)
    FW_root = r;

  FW_replaceWidgets($("html"));

  // Fix the td count by setting colspan on the last column
  $("table.block.wide").each(function(){        // table
    var id = $(this).attr("id");
    if(!id || id.indexOf("TYPE") != 0)
      return;
    var maxTd=0, tdCount=[], tbl = $(this);
    $(tbl).find("> tbody > tr").each(function(){         // count the td's
      var cnt = 0, row=this;
      $(row).find("> td").each(function(){ 
        var cs = $(this).attr("colspan");
        cnt += parseInt(cs ? cs : 1);
      });
      if(maxTd < cnt)
        maxTd = cnt;
      tdCount.push(cnt);
    });
    $(tbl).find("> tbody> tr").each(function(){         // set the colspan
      var tdc = tdCount.shift();
      $(this).find("> td:last").each(function(){
        var cs = $(this).attr("colspan");
        $(this).attr("colspan", maxTd-tdc+(cs ? parseInt(cs) : 1));
      });
    });
  });

  $("form input.get[type=submit]").click(function(e) { //"get" via XHR to dialog
    e.preventDefault();
    var cmd = "", el=this;
    $(el).parent().find("input,[name]").each(function() {
      cmd += (cmd?"&":"")+encodeURIComponent($(this).attr("name"))+
                      "="+encodeURIComponent($(this).val());
    });
    FW_cmd(FW_root+"?"+cmd+"&XHR=1&addLinks=1", function(data) {
      if(!data.match(/^[\r\n]*$/)) {// ignore empty answers
        var ma = /^<html>([\s\S]*)<\/html>/.exec(data);
        if(ma) {
          FW_okDialog(ma[1], el);
        } else {
          FW_okDialog('<pre>'+data+'</pre>', el);
        }
      }
    });
  });
  

  $("#saveCheck")
    .css("cursor", "pointer")
    .click(function(){
      var parent = this;
      FW_cmd(FW_root+"?cmd=save ?&XHR=1", function(data) {
        FW_okDialog('<pre>'+data+'</pre>',parent);
      });
    });

  $("form").each(function(){   // main input special cases
    var input = $(this).find("input.maininput");
    if(!input.length)
      return;
    $(this).on("submit", function(e) {
      var val = $(input).val();
      if(val.match(/^\s*ver.*/)) {              // version
        e.preventDefault();
        $(input).val("");
        return FW_showVersion(val);
        
      } else if(val.match(/^\s*shutdown/)) {    // shutdown
        FW_cmd(FW_root+"?XHR=1&cmd="+val);
        $(input).val("");
        return false;

      } else if(val.match(/^\s*l\s/)) {        // l dev
        var m = val.match(/^\s*l\s+(.*)/);
        location.href = FW_root+"?detail="+m[1];
        e.preventDefault();
        return false;

      } else if(val.match(/^\s*get\s+/)) {      // get
        // make get use xhr instead of reload
        //return true;
        FW_cmd(FW_root+"?cmd="+encodeURIComponent(val)+"&XHR=1", function(data){
          if( !data.match( /^<html>[\s\S]*<\/html>/ ) ) {
            data = data.replace( '<', '&lt;' );
            data = '<pre>'+data+'</pre>';
          }
          if( location.href.indexOf('?') === -1 )
            $('#content').html(data);
          else
            FW_okDialog(data);
        });

        e.preventDefault();
        $(input).val("");
        return false;
      }

      return true;
    });
  });

  $("table.attributes tr div.dname")    // Click on attribute fills input value
    .each(function(){
      $(this)
        .html('<a>'+$(this).html()+'</a>')
        .css({cursor:"pointer"})
        .click(function(){
          var attrName = $(this).text();
          var sel = "#sel_attr"+$(this).attr("data-name").replace(/\./g,'_');
          if($(sel+" option[value='"+attrName+"']").length == 0)
            $(sel).append('<option value="'+attrName+'">'+attrName+'</option>');
          $(sel).val(attrName);
          FW_detailSelect(sel, true);
          $(sel).trigger("change");
        });
    });

  $("[name=icon-filter]").on("change keyup paste", function() {
    clearTimeout($.data(this, 'delayTimer'));
    var wait = setTimeout(FW_filterIcons, 300);
    $(this).data('delayTimer', wait);
  });

  $("pre.motd").each(function(){ // add links for passwort setting
    var txt = $(this).text();
    txt = txt.replace(/(configuring|define|attr) .*/g, function(x) {
      return "<a href='#'>"+x+"</a>";
    });
    $(this).html(txt);
    $(this).find("a").click(function(){
      var txt = $(this).text();
      var ma = txt.match(/configuring.*device (.*)/);   // ??
      if(ma)
        location.href = FW_root+"?detail="+ma[1];
      FW_cmd(FW_root+"?cmd="+encodeURIComponent(txt)+"&XHR=1",
        function(data){
          if(txt.indexOf("attr") == 0) $("pre.motd").html("");
          if(txt.indexOf("define") == 0)
            location.href = FW_root+"?detail=allowed";
        });
    });
  });

  var sa = location.search.substring(1).split("&");
  for(var i = 0; i < sa.length; i++) {
    var kv = sa[i].split("=");
    FW_urlParams[kv[0]] = decodeURIComponent(kv[1]);
  }

  $("select[id^=sel_attr],select[id^=sel_set],select[id^=sel_get]")
  .change(function(){ // online help
    var val = $(this).val();
    var m = $(this).attr("name").match(/arg.(set|get|attr)(.*)/);
    if(!m)
      return;
    $("#devSpecHelp").remove();
    var sel=this, devName=m[2], selType=m[1];
    var group = $(this).parent().find(':selected').parent().attr('label');
    FW_displayHelp(devName, sel, selType, val, group);
  });

  FW_smallScreenCommands();
  FW_inlineModify();
  FW_detLink();
  FW_treeMenu();

  $("body").attr("data-os", FW_os);
  // automatic reload for style change
  if(location.search.indexOf("cmd=style%20select") > 0) {
    $('a[href*="style set"],a[onclick*="style set"]').each(function(){
      var href = $(this).attr("href");
      if(!href && (href = $(this).attr("onclick")))
        href = href.substr(15,href.length-16);
      $(this).click(function(e){
        e.preventDefault();
        FW_cmd(href+"&XHR=1", function(data) { location.reload(true); });
      });
    });
  }

}

function
FW_displayHelp(devName, sel, selType, val, group)
{
  if(group) {
    if(group.indexOf("userattr") >= 0)
      return;
    devName = (group == "framework" ? "commandref" : group);
  }

  FW_getHelp(devName, function(data) { // show either the next or the outer li
    $("#content")
      .append("<div id='workbench' style='display:none'></div>");
    var wb = $("#content > #workbench");
    wb.html(data);

    var mtype = wb.find("a[id]").attr("id"), aTag;
    if(!mtype)
      mtype = wb.find("a[name]").attr("name");

    if(devName == "commandref")
      mtype = "";

    if(mtype) {             // current syntax: FHEMWEB-attr-webCmd
      var mv = (""+mtype+"-"+selType+"-"+val).replace(/[^a-z0-9_-]/ig,'_');
      aTag = wb.find("a[id="+mv+"]");
      if(!$(aTag).length) { // old style #1 syntax: FHEMWEBwebCmd
        mv = (""+mtype+val).replace(/[^a-z0-9_-]/ig,'_');
        aTag = wb.find("a[name="+mv+"]");
      }
    }
    if(!$(aTag).length) { // old style #2 syntax : webCmd
      var v = (val).replace(/[^a-z0-9_-]/ig,'_');
      aTag = wb.find("a[name="+v+"]");
    }

    if(!$(aTag).length) { // regexp attributes, like backend_.*
      wb.find("a[id^='"+mtype+"-"+selType+"-'][data-pattern]").each(
        function() {
          var dp = $(this).attr("data-pattern");
          // if(!$(aTag).length && val.match(dp)) {
          if(val.match(dp)) {
            log("Searching for "+val+", found data-pattern "+dp);
            aTag = this;
          }
        });
    }

    if($(aTag).length) {
      var liTag = $(aTag).next("li");
      if(!$(liTag).length)
        liTag = $(aTag).parent("li");
      if(!$(liTag).length)
        liTag = $(aTag).parent().next("li");
      $("#devSpecHelp").remove(); // shown only one if FHEM is slow
      if($(liTag).length) {
        $(sel).closest("div[cmd='"+selType+"']")
           .after('<div class="makeTable" id="devSpecHelp"></div>')
        $("#devSpecHelp").html($(liTag).html());
      }
    }
    wb.remove();

  });
}

var FW_helpData={};
function
FW_getHelp(dev, fn)
{
  if(FW_helpData[dev])
    return fn(FW_helpData[dev]);

  if(dev == "commandref") {
    var lang = $("body").attr("data-language");
    var url = FW_root+"/docs/commandref_frame"+
                (lang == "EN" ? "" : "_"+lang)+".html";
    $.ajax({
      url:url, headers: { "cache-control": "no-cache" },
      success: function(data, textStatus, req){
        FW_helpData[dev] = data;
        return fn(data);
      },
      error:function(xhr, status, err) { log("E:"+err+"/"+status); }
    });
    return;
  }

  FW_cmd(FW_root+"?cmd=help "+dev+"&XHR=1", function(data) {
    if(data.match(/^<html>No help found/) &&
       !dev.match(" DE")) // for our german only friends
      return FW_getHelp(dev+" DE", fn);
    FW_helpData[dev] = data;
    return fn(data);
  });
}

function
FW_showVersion(val)
{
  FW_cmd(FW_root+"?cmd="+encodeURIComponent(val)+"&XHR=1", function(data){
    var list = Object.keys(FW_version);
    list.sort();
    for(var i1=0; i1<list.length; i1++) {
      var ma = /\$Id: ([^ ]*) (.*) \$/.exec(FW_version[list[i1]]);
      if(ma) {
        if(ma[1].length < 26)
          ma[1] = (ma[1]+"                            ").substr(0,26);
        data += "\n"+ma[1]+" "+ma[2];
      }
    }
    FW_okDialog('<pre>'+data+'</pre>');
  });
  return false;
}

function
FW_filterIcons()
{
  var icons = $('.dist[title]');
  icons.show();

  var filterText = $('[name=icon-filter]').val();
  if (filterText != '') {
    var re = RegExp(filterText,"i");
    icons.filter(function() {
      return !re.test(this.title);
    }).hide();
  }
}


function
FW_deleteDevice(dev)
{
  var cmd = addcsrf(FW_root+"?cmd=delete "+dev);

  var cd = $("body").attr("data-confirmDelete");
  if(!cd || cd == 0) {
    location.href = cmd;
    return;
  }

  var div = $("<div>");
  $(div).html("Do you really want to delete "+dev+"?<br><br>"+
    "<input type='checkbox' name='noconf'> Skip this dialog in the future");
  $("body").append(div);

  $(div).dialog({
    dialogClass:"no-close", modal:true, width:"auto", closeOnEscape:true, 
    maxWidth:$(window).width()*0.9, maxHeight:$(window).height()*0.9,
    buttons: [
      {text:"Yes", click:function(){ doClose(); location.href = cmd; }},
      {text:"No",  click:doClose} ],
    close: doClose
  });

  function
  doClose()
  {
    var wn = $("body").attr("data-webName");
    if($(div).find("input:checked").length)
      FW_cmd(FW_root+"?cmd=attr "+wn+" confirmDelete 0&XHR=1");
    $(this).dialog("close"); $(div).remove();
  }
}

function
FW_renameDevice(dev)
{
  var div = $("<div>");
  $(div).html('Rename '+dev+' to:<br><br><input type="text" size="30">');
  $("body").append(div);

  $(div).dialog({
    dialogClass:"no-close", modal:true, width:"auto", closeOnEscape:true, 
    maxWidth:$(window).width()*0.9, maxHeight:$(window).height()*0.9,
    buttons: [
      {text:"Rename", click:function(){ 
        var nn = $(div).find("input").val();
        if(!nn.match(/^[a-z0-9._]*$/i))
          return FW_okDialog("Illegal characters in the new name");
        location.href = addcsrf(FW_root+"?cmd=rename "+dev+" "+nn);
      }},
      {text:"Cancel", click:doClose} ],
    close: doClose
  });

  function
  doClose()
  {
    $(this).dialog("close"); $(div).remove();
  }
}

// Show the webCmd list in a dialog if: smallScreen & hiddenroom=detail & room
function
FW_smallScreenCommands()
{
  if($("div#menu select").length == 0 ||           // not SmallScreen
     $("div#content").attr("room") == undefined || // not room Overview
     $("div#content div.col1 a").length > 0)       // no hiddenroom=detail
    return;

  $("div#content div.col1").each(function(){
    var tr = $(this).closest("tr");
    if($(tr).find("> td").length <= 2)
      return;
    $(this).html("<a href='#'>"+$(this).html()+"</a>");
    $(this).find("a").click(function(){
      var t = $("<table></table>"), row=0;
      $(tr).find("> td").each(function(){
        $(t).append("<tr></tr>");
        if(row++ == 0) {
          $(t).find("tr:last").append($(this).find("a").html());
        } else {
          $(this).attr("data-orig", 1);
          this.orig=$(this).parent();
          $(t).find("tr:last").append($(this).detach());
        }
      });
      FW_okDialog(t, this, function(){
        $("#FW_okDialog [data-orig]").each(function(){
          $(this).detach().appendTo(this.orig);
        });
      });
    });
  });
}


if(window.jQuery) {
  $(document).ready(FW_jqueryReadyFn);

} else {
  // FLOORPLAN compatibility
  loadScript("pgm2/jquery.min.js", function() {
    loadScript("pgm2/jquery-ui.min.js", function() {
      FW_jqueryReadyFn();
    }, true);
  }, true);
}

// FLOORPLAN compatibility
function
FW_delayedStart()
{
  setTimeout("FW_longpoll()", 100);
}
    

var FW_logStack=[];
function
log(txt)
{
  var d = new Date();
  var ms = ("000"+(d.getMilliseconds()%1000));
  ms = ms.substr(ms.length-3,3);
  var lTxt = d.toTimeString().substring(0,8)+"."+ms+" "+txt;
  if(typeof window.console != "undefined")
    console.log(lTxt);

  if(FW_jsLog==1 && FW_longpollType == "websocket") {
    FW_logStack.push(txt);
    if(FW_pollConn && FW_pollConn.readyState == FW_pollConn.OPEN) {
      while(FW_logStack.length) {
        txt = '{Log 1, "jsLog: '+FW_logStack.shift().replace(/"/g, "'")+'"}';
        console.log(txt);
        FW_pollConn.send(txt);
      }
    }
  }
}

function
addcsrf(arg)
{
  if(typeof FW_csrfToken != "undefined") {
    arg = arg.replace(/&fwcsrf=[^&]*/,'');
    arg += '&fwcsrf='+encodeURIComponent(FW_csrfToken);
  }
  return arg;
}

function
FW_csrfRefresh(callback)
{
  log("FW_csrfRefresh, last was "+(FW_csrfOk ? "ok":"bad"));
  if(!FW_csrfOk)        // avoid endless loop
    return;
  $.ajax({
    url:location.pathname+"?XHR=1",
    success: function(data, textStatus, request){
      FW_csrfToken = request.getResponseHeader('x-fhem-csrftoken');
      FW_csrfOk = false;
      if(callback)
        callback();
    }
  });
}

var FW_cmdStack=[];
function
FW_cmd(arg, callback, rep)
{
  if(arg.length < 120)
    log("FW_cmd:"+arg);
  else
    log("FW_cmd:"+arg.substr(0,120)+"...");
  $.ajax({
    url:addcsrf(arg)+'&fw_id='+$("body").attr('fw_id'),
    headers: { "cache-control": "no-cache" },
    dataType: "text",
    method:'POST',
    success: function(data, textStatus, req){
      FW_csrfOk = true;
      if(callback)
        callback(req.responseText);
      else if(req.responseText)
        FW_errmsg(req.responseText, 5000);
      var todo = FW_cmdStack.shift();
      if(todo) {
        log("FW_cmd retry #"+todo.rep);
        FW_cmd(todo.arg, todo.callback, todo.rep);
      }
    },
    error:function(xhr, status, err) {
      // iOS 13+ is not queueing requests, have to do it myself. Forum #116962
      if(xhr.status == 0 && xhr.readyState == 0 && (!rep || rep < 10)) {
        FW_cmdStack.push({ arg:arg, callback:callback, rep:(rep?rep+1:1)});

      } else if(xhr.status == 400 && typeof FW_csrfToken != "undefined") {
        FW_csrfToken = "";
        FW_csrfRefresh(function(){FW_cmd(arg, callback)});

      } else {
        log("FW_cmd error: "+status+"/"+JSON.stringify(xhr));
      }
    }
  });
}

function
FW_errmsg(txt, timeout)
{
  log("ERRMSG:"+txt+"<");
  var errmsg = document.getElementById("errmsg");
  if(!errmsg) {
    if(txt == "")
      return;
    errmsg = document.createElement('div');
    errmsg.setAttribute("id","errmsg");
    document.body.appendChild(errmsg);
  }
  if(txt == "") {
    document.body.removeChild(errmsg);
    return;
  }
  errmsg.innerHTML = txt;
  if(timeout)
    setTimeout("FW_errmsg('')", timeout);
}

function
FW_okDialog(txt, parent, removeFn)
{
  $("#FW_okDialog").remove();
  var div = $("<div id='FW_okDialog'>");
  $(div).html(txt);
  $("body").append(div);
  var oldPos = $("body").scrollTop();
  $(div).dialog({
    dialogClass:"no-close", modal:true, width:"auto", closeOnEscape:true, 
    maxWidth:$(window).width()*0.9, maxHeight:$(window).height()*0.9,
    buttons: [{text:"OK", click:function(){
      $(this).dialog("close");
      if(removeFn)
        removeFn();
      $(div).remove();
    }}]
  });

  FW_replaceWidgets(div);
  $(div).find("a").each(function(){FW_replaceLink(this);}); //Forum #33766

  if(parent)
    $(div).dialog( "option", "position", {
      my: "left top", at: "right bottom",
      of: parent, collision: "flipfit"
    });
  setTimeout(function(){$("body").scrollTop(oldPos);}, 1); // Not ideal.
}

function
FW_menu(evt, el, arr, dis, fn, embedEl)
{
  if(!embedEl)
    evt.stopPropagation();
  if($("#fwmenu").length) {
    delfwmenu();
    return;
  }

  var html = '<ul id="fwmenu">';
  for(var i=0; i<arr.length; i++) {
    html+='<li class="'+ ((dis && dis[i]) ? 'ui-state-disabled' : '')+'">'+
            '<a row="'+i+'" href="#">'+arr[i]+'</a></li>';
  }
  html += '</ul>';
  $("body").append(html);

  function
  delfwmenu()
  {
    $("ul#fwmenu").remove();
    $('html').unbind('click.fwmenu');
  }

  var wt = $(window).scrollTop();
  $("#fwmenu")
    .menu({
      select: function(e,ui) { // changes the scrollTop();
        e.stopPropagation();
        fn($(e.currentTarget).find("[row]").attr("row"));
        delfwmenu();
        setTimeout(function(){ $(window).scrollTop(wt) }, 1); // Bug in select?
      }
    });

  var off = $(el).offset();
  if(embedEl) {
    var embOff = $(embedEl).offset();
    off.top += embOff.top;
    off.left += embOff.left;
  }
  var dH = $("#fwmenu").height(), dW = $("#fwmenu").width(), 
      wH = $(window).height(), wW = $(window).width();
  var ey = off.top+dH+20, ex = off.left+dW;
  if(ex>wW && ey>wH) { off.top -= dH; off.left -= (dW+16);
  } else if(ey > wH) { off.top -= dH; off.left += 20;
  } else if(ex > wW) {                off.left -= (dW+16);
  } else {             off.top += 20;
  }

  $("#fwmenu").css(off);
  $('html').bind('click.fwmenu', function() { delfwmenu(); });
}

function
FW_getLink(el)
{
  var attr = $(el).attr("href");
  if(!attr) {
    attr = $(el).attr("onclick");   // Tablet/smallScreen version
    if(!attr)
      return "";
    attr = attr.replace(/^location.href='/,'');
    attr = attr.replace(/'$/,'');
  }
  return attr;
}

function
FW_replaceLink(el)
{
  var attr = FW_getLink(el);
  if(!attr)
    return;

  var ma = attr.match(/^(.*\?)(cmd[^=]*=.*)$/);
  if(ma == null || ma.length == 0 || !ma[2].match(/=(save|set)/)) {
    ma = attr.match(new RegExp("^"+FW_root)); // Avoid "Connection lost" @iOS
    if(ma) {
      $(el).click(function(e) {
        // Open link in window/tab, Forum #39154
        if(e.shiftKey || e.ctrlKey || e.metaKey || e.button == 1)
          return;
        e.preventDefault();
        FW_leaving = 1;
        if($(el).attr("target") == "_blank") {
          window.open(attr, '_blank').focus();
        } else {
          location.href = attr;
        }
      });
    }
    return;
  }
  $(el).removeAttr("href");
  $(el).removeAttr("onclick");
  $(el).click(function() { 
    attr = attr.replace(/&.*$/,''); // remove unnecessary params, forum: #97351
    FW_cmd(attr+"&XHR=1", function(txt){
      if(!txt)
        return;
      if(ma[2].match(/=set/)) // Forum #38875
        FW_okDialog('<pre>'+txt+'<pre>', el);
      else
        FW_errmsg(txt, 5000);
    });
  });
  $(el).css("cursor", "pointer");
}

function
FW_htmlQuote(text)
{
  return text.replace(/&/g, '&amp;')    // Same as in 01_FHEMWEB
             .replace(/</g, '&lt;')
             .replace(/>/g, '&gt;');
}

function
FW_inlineModify()       // Do not generate a new HTML page upon pressing modify
{
  var cm;

  if( typeof AddCodeMirror == 'function' ) {
    // init codemirror for FW_style edit textarea
    AddCodeMirror($('textarea[name="data"]'));
  }

  $('#DEFa').click(function(){
    var old = $('#edit').css('display');
    $('#edit').css('display', old=='none' ? 'block' : 'none');
    $('#disp').css('display', old=='none' ? 'none' : 'block');
    if( typeof AddCodeMirror == 'function' ) {
      var s=document.getElementById("edit").getElementsByTagName("textarea");
      AddCodeMirror(s[0], function(pcm) {cm = pcm;});
    }
    });
    
  // Set and attr 
  $("div input.psc[type=submit]:not(.get)").click(function(e){
    e.preventDefault();
    var frm = $(this).closest("form");
    var newDef = typeof cm !== 'undefined' ?
                 cm.getValue() : frm.find("textarea").val();
    var cmd = $(this).attr("name")+"="+$(this).attr("value")+" "+newDef;
    var isDef = true, reloadIfOk = false;

    if(newDef == undefined || $(this).attr("value").indexOf("modify") != 0) {
      isDef = false;
      var div = $(this).closest("div.makeSelect");
      var devName = $(div).attr("dev"),
          cmd = $(div).attr("cmd");
      var sel = frm.find("select");
      var arg = $(sel).val();
      var ifid = (devName+"-"+arg).replace(/([^_a-z0-9])/gi,
                                   function(m){ return "\\"+m });
      if($(".dval[informid="+ifid+"]").length == 0) {// No reading with this name
        if(cmd == "attr" || (cmd == "set" && arg == "attrTemplate")) {
          reloadIfOk = true;
        } else {
          $(this).unbind('click').click();// No element found to replace, reload
          return;
        }
      }
      // Make it similar to submit: values joined by ,
      var nd=frm.find("[name^=val]").map(function(){return $(this).val()}).get();
      newDef = nd.length ? nd.join(",") : frm.find("input:text").val();
      cmd = $(this).attr("name")+"="+cmd+" "+devName+" "+arg+" "+newDef;
    }
    FW_cmd(FW_root+"?"+encodeURIComponent(cmd)+"&XHR=1", function(resp){
      if(!resp && reloadIfOk) {
        var hr = location.href+"";
        location.href = hr+     // retain fw_id
              (hr.match(/fw_id=\d+/) ? "" : '&fw_id='+$("body").attr('fw_id'));

      }
      if(resp) {
        if(!resp.match(/^<html>[\s\S]*<\/html>/ ) ) {
          resp = FW_htmlQuote(resp);
          if(resp.indexOf("\n") >= 0)
            resp = '<pre>'+resp+'</pre>';
        }
        return FW_okDialog(resp);
      }
      if(isDef) {
        newDef = FW_htmlQuote(newDef);
        if(newDef.indexOf("\n") >= 0)
          newDef = '<pre>'+newDef+'</pre>';
        $("div#disp").html(newDef).css("display", "");
        $("div#edit").css("display", "none");
      }
    });
  });
}

// Fill the "detLink" line with life
function
FW_detLink()
{
  $("div.rawDef a").each(function(){       // Help on detail window
    var dev = FW_getLink(this).split(" ").pop().split("&")[0];
    $(this).unbind("click");
    $(this).attr("href", "#"); // Desktop: show underlined Text
    $(this).removeAttr("onclick");

    $(this).click(function(evt){
      if($("#rawDef").length) {
        $("#rawDef").remove();
        return;
      }
      var textAreaStyle = typeof AddCodeMirror == 'function'?'opacity:0':'';

      $("#content").append('<div id="rawDef">'+
          '<textarea id="td_rawDef" rows="25" cols="60" style="width:99%; '+
                textAreaStyle+'"/>'+
          '<button>Execute commands</button>'+
          ' Dump "Probably associated with" too <input type="checkbox">'+
        '<br><br></div>');

      var cmVar;

      function
      fillData(opt)
      {
        var s = $('#rawDef textarea');

        FW_cmd(FW_root+"?cmd=list "+opt+" "+dev+"&XHR=1", function(data) {
          var re = new RegExp("^define", "gm");
          data = data.replace(re, "defmod");
          s.val(data);

          var off = $("#rawDef").position().top-20;
          $('body, html').animate({scrollTop:off}, 500);
          $("#rawDef button").hide();

          var propertychange = function() {
            var nData = $("#rawDef textarea").val();
            if(nData != data)
              $("#rawDef button").show();
            else
              $("#rawDef button").hide();
          };

          s.bind('input propertychange', propertychange);

          if(cmVar) {
            cmVar.setValue(data);

          } else if(typeof AddCodeMirror == 'function') {
            AddCodeMirror(s, function(cm) {
              cmVar = cm;
              cm.on("change", function() {
                s.val(cm.getValue());
                propertychange();
              })
            });
          }

        });
      }
      fillData("-r");

      $("#rawDef input").click(function(){fillData(this.checked ?"-R":"-r")});

      $("#rawDef button").click(function(){
        FW_execRawDef($("#rawDef textarea").val());
      });
    });

  });

  $("#detLink .devSpecHelp a").each(function(){       // Help on detail window
    var dev = FW_getLink(this).split("#").pop();
    $(this).unbind("click");
    $(this).attr("href", "#"); // Desktop: show underlined Text
    $(this).removeAttr("onclick");

    $(this).click(function(evt){
      if($("#devSpecHelp").length) {
        $("#devSpecHelp").remove();
        return;
      }
      FW_getHelp(dev, function(data){
        $("#content").append('<div id="devSpecHelp"></div>');
        $("#devSpecHelp").html(data);
        var off = $("#devSpecHelp").position().top-20;
        $('body, html').animate({scrollTop:off}, 500);
      });
    });
  });


  $("#detLink select#moreCmds").change(function(){
    var cmd = $(this).find("option:selected").attr("data-cmd");
    if(!cmd)
      return;
    var m = cmd.match(/^([^ ]+) (.*)$/);
    if(!m)
      return;

    if(m[1] == "forumCopy") {
      FW_cmd(FW_root+"?cmd=list -r -i "+m[2]+"&XHR=1", function(data) {
        data = '[code]'+data+'[/code]';
        var okTxt = '"forum ready" definition copied to the clipboard.';
        var errTxt = 'Could not copy the text: ';
        var ok;
        if(navigator.clipboard) {
          navigator.clipboard.writeText(data).then(
            function(){ FW_okDialog(okTxt) },
            function(err){ FW_okDialog(errTxt+err) });

        } else {
          var ta = document.createElement("textarea");
          ta.value = data;
          ta.style.top = ta.style.left = "0";
          ta.style.position = "fixed";
          document.body.appendChild(ta);
          ta.focus();
          ta.select();
          try {
            if(document.execCommand('copy'))
              FW_okDialog(okTxt);
             else
              FW_okDialog(errTxt);
          } catch (err) {
            log('Copy:'+err);
            FW_okDialog(errTxt+err);
          }
          document.body.removeChild(ta);
        }
      });

    } else if(m[1] == "rename") {
      FW_renameDevice(m[2]);

    } else if(m[1] == "delete") {
      FW_deleteDevice(m[2]);

    } else {
      location.href = addcsrf(FW_root+"?cmd="+cmd);

    }
  });
}

function
FW_execRawDef(data)
{
  var arr = data.split("\n"), str="", i1=-1;
  function
  doNext()
  {
    if(++i1 >= arr.length) {
      if($("#FW_okDialog").length) // F2F remote cmd execution
        return;
      return FW_okDialog("Executed everything, no errors found.");
    }
    str += arr[i1];
    if(arr[i1].charAt(arr[i1].length-1) === "\\") {
      str += "\n";
      return doNext();
    }
    if(str != "") {
      str = str.replace(/\\\n/g, "\n");
      FW_cmd(FW_root+"?cmd="+encodeURIComponent(str)+"&XHR=1",
      function(r){
        if(r)
          return FW_okDialog('<pre>'+r+'</pre>');
        str = "";
        doNext();
      });
    } else {
      doNext();
    }
  }
  doNext();
}

var FW_arrowDown="", FW_arrowRight="";
function
FW_treeMenu()
{
  var a = $("a").get(0);
  var col = 'rgb(39, 135, 38)';
  if(window.getComputedStyle && a)
    col = getComputedStyle(a,null).getPropertyValue('color'); 
  FW_arrowRight = 'data:image/svg+xml;utf8,<svg viewBox="0 0 1792 1792" xmlns="http://www.w3.org/2000/svg"><path fill="gray" d="M1171 960q0 13-10 23l-466 466q-10 10-23 10t-23-10l-50-50q-10-10-10-23t10-23l393-393-393-393q-10-10-10-23t10-23l50-50q10-10 23-10t23 10l466 466q10 10 10 23z"/></svg>'
      .replace('gray', col);
  FW_arrowDown =FW_arrowRight.replace('/>',' transform="rotate(90,896,896)"/>');

  var fnd;

  $("div#menu table.room").each(function(){     // one loop per Block
    var t = this, ma = {};
    $(t).find("td > div > a > span").each(function(e){
      var span = this, spanTxt = $(span).text().replace(/,/g,'');
      var ta = spanTxt.split("->");
      if(ta.length <= 1)
        return;
      fnd = true;
      var nxt="", lst="", tr=$(span).closest("tr");
      for(var i1=0; i1<ta.length-1; i1++) {
        nxt += "->"+ta[i1];
        if(!ma[nxt]) {
          $(tr).before("<tr class='menuTree closed level"+i1+"' "+
              "data-mTree='"+lst+"' data-nxt='"+nxt+"'>"+
              "<td><div><a href='#'>"+ta[i1]+"</a><div></div></div></td></tr>");
        }
        ma[nxt] = true;
        lst = nxt;
      }
      $(span).html(ta[ta.length-1]);
      $(tr).attr("data-mTree", nxt)
           .addClass("menuTree level"+(ta.length-1));
    });
  });

  if(fnd) {
    $("head").append(
      "<style>"+
        "tr.menuTree { cursor:pointer; }"+
        "tr.menuTree.level1 > td > div { margin-left:10px; }"+
        "tr.menuTree.level2 > td > div { margin-left:20px; }"+
        "tr.menuTree.level3 > td > div { margin-left:30px; }"+
        "tr.menuTree.open { font-weight: bold; }"+
        "tr.menuTree > td > div > div { "+
          "display:inline-block; width:1em; height:1em; float:right;"+
          "background-size: contain; background-repeat: no-repeat;"+
        "}"+
      "</style>");
    var t = $("div#menu table.room");
    $(t).find("tr[data-mTree]").not(".level0").hide();
    $(t).find("tr.menuTree").click(function(){treeClick(this)});
    $(t).find("tr.menuTree > td > div > div")
        .css("background-image", "url('"+FW_arrowRight+"')");
    var selRoom = $("div#content").attr("room");
    if(selRoom) {
      var ta = selRoom.split("->"), nxt="";
      for(var i1=0; i1<ta.length-1; i1++) {
        nxt += FW_escapeSelector("->"+ta[i1]);
        treeClick($(t).find("tr.menuTree[data-nxt="+nxt+"]"));
      }
    }
  }

  function
  treeClick(el)
  {
    var tgt = FW_escapeSelector($(el).attr("data-nxt"));
    if($(el).hasClass("closed")) {
      $(el).closest("table").find("tr[data-mTree="+tgt+"]").show();
      $(el).find("div>div").css("background-image", "url('"+FW_arrowDown+"')");
    } else {
      $(el).closest("table").find("tr[data-mTree^="+tgt+"]")
        .hide().filter('[data-nxt]').addClass("closed").removeClass("open");
      $(el).find("div>div").css("background-image", "url('"+FW_arrowRight+"')");
    }
    $(el).toggleClass("closed");
    $(el).toggleClass("open");
  };
}

function
FW_escapeSelector(s)
{
  if(typeof s != 'string')
    return s;
  return s.replace(/[ .#\[\]>,]/g, function(r) { return '\\'+r });
}

/*************** LONGPOLL START **************/
var FW_pollConn;
var FW_longpollOffset = 0;
var FW_leaving;
var FW_lastDataTime=0;

function
FW_doUpdate(evt)
{
  var errstr = "Connection lost, trying a reconnect every 5 seconds.";
  var input="";
  var retryTime = 5000;
  var now = new Date()/1000;

  // d: array
  // d[0]: informid
  // d[1]: if the informid Widget has setValueFn, arg for this
  // d[2]: else replace the html with this
  function
  setValue(d) // is Callable from eval below
  {
    $("[informId='"+d[0]+"']").each(function(){
      if(this.setValueFn) {     // change the select/etc value
        this.setValueFn(d[1].replace(/\n/g, '\u2424'));

      } else {
        if(d[2].match(/\n/) && !d[2].match(/<.*>/)) // format multiline
          d[2] = '<html><pre>'+d[2]+'</pre></html>';

        var ma = /^<html>([\s\S]*)<\/html>/.exec(d[2]);
        if(!d[0].match("-")) { // not a reading
          $(this).html(d[2]);
          FW_replaceWidgets($(this));

        } else if(ma) {
          $(this).html(ma[1]);
          FW_replaceWidgets($(this));

        } else {
          $(this).text(d[2]);

        }

        if(d[0].match(/-ts$/))  // timestamps
          $(this).addClass('changed');
        $(this).find("a").each(function() { FW_replaceLink(this) });
      }
    });
  }

  // iOS closes HTTP after 60s idle, websocket after 240s idle
  if(now-FW_lastDataTime > 59) {
    errstr="";
    retryTime = 100;
  }
  FW_lastDataTime = now;

  // Websocket starts with Android 4.4, and IE10
  if(typeof WebSocket == "function" && evt && evt.target instanceof WebSocket) {
    if(evt.type == 'close' && !FW_leaving) {
      FW_errmsg(errstr, retryTime-100);
      if(FW_pollConn) // Race-condition(?) # 112181
        FW_pollConn.close();
      FW_pollConn = undefined;
      setTimeout(FW_longpoll, retryTime);
      return;
    }
    input = evt.data;
    FW_longpollOffset = 0;

  } else if(FW_pollConn != undefined) {
    if(FW_pollConn.readyState == 4 && !FW_leaving) {
      if(FW_pollConn.status == "400") {
        location.reload();
        return;
      }
      FW_errmsg(errstr, retryTime-100);
      setTimeout(FW_longpoll, retryTime);
      return;
    }

    if(FW_pollConn.readyState != 3)
      return;

    input = FW_pollConn.responseText;
  }

  var devs = new Array();
  if(!input || input.length <= FW_longpollOffset)
    return;

  FW_serverLastMsg = (new Date()).getTime()/1000;
  for(;;) {
    var nOff = input.indexOf("\n", FW_longpollOffset);
    if(nOff < 0)
      break;
    var l = input.substr(FW_longpollOffset, nOff-FW_longpollOffset);
    FW_longpollOffset = nOff+1;

    if(l != '[""]') // jsLog answer
      log("Rcvd: "+(l.length>132 ? l.substring(0,132)+"...("+l.length+")":l));
    if(!l.length)
      continue;
    if(l.indexOf("<")== 0) {  // HTML returned by proxy, if FHEM behind is dead
      FW_closeConn();
      FW_errmsg(errstr, retryTime-100);
      setTimeout(FW_longpoll, retryTime);
      return;
    }
    var d = JSON.parse(l);
    if(d.length != 3)
      continue;

    if( d[0].match(/^#FHEMWEB:/) ) {
      try {
        eval(d[1]);
      } catch(e) {
        if($("body").attr("data-confirmJSError") != 0)
          FW_okDialog("#FHEMWEB notification:<br>"+d[1]+"<br>"+e);
      }

    } else {
      setValue(d);

    }

    // updateLine is deprecated, use setValueFn
    for(var w in FW_widgets)
      if(FW_widgets[w].updateLine && !FW_widgets[w].second)
        FW_widgets[w].updateLine(d);

    devs.push(d);
  }

  // used for SVG to avoid double-reloads
  for(var w in FW_widgets)
    if(FW_widgets[w].updateDevs && !FW_widgets[w].second)
      FW_widgets[w].updateDevs(devs);

  // reset the connection to avoid memory problems
  if(FW_longpollOffset > 1024*1024 && FW_longpollOffset==input.length)
    FW_longpoll();
}

function
FW_closeConn()
{
  FW_leaving = 1;
  if(!FW_pollConn)
    return;
  if(typeof FW_pollConn.close ==  "function")
    FW_pollConn.close();
  else if(typeof FW_pollConn.abort ==  "function")
    FW_pollConn.abort();
  FW_pollConn = undefined;
}

function
FW_longpoll()
{
  FW_closeConn();

  FW_leaving = 0;
  FW_longpollOffset = 0;

  // Build the notify filter for the backend
  var filter = $("body").attr("longpollfilter");
  filter = filter ? decodeURIComponent(filter) : "";

  var retry;
  if(filter == "") {
    $("embed").each(function() {        // wait for all embeds to be there
      if(retry)
        return;
      var ed = FW_getSVG(this);
      if(!retry && ed == undefined && filter != ".*" && --embedLoadRetry > 0) {
        retry = 1;
        setTimeout(FW_longpoll, 100);
        return;
      }
      if(ed && $(ed).find("svg[flog]").attr("flog"))
        filter=".*";
    });
    if(retry)
      return;
  }

  if(filter == "") {
    if(FW_urlParams.room)
        filter="room="+FW_urlParams.room
                      .replace(/[[\]().+*?]/g, function(r){return '\\'+r});
    if(FW_urlParams.detail) filter=FW_urlParams.detail;
  }

  if($("#floorplan").length>0) //floorplan special
    filter += ";iconPath="+$("body").attr("name");

  if(filter == "") {
    var content = document.getElementById("content");
    if(content) {
      var room = content.getAttribute("room");
      if(room)
        filter="room="+room
                      .replace(/[[\]().+*?]/g, function(r){return '\\'+r});
    }
  }

  // use devspec directly if room is dynamic (#devspec=<devspec>)
  filter = filter.replace( 'room=#devspec=', '' );
  filter = filter.replace( 'room=%23devspec%3d', '' );

  var iP = $("body").attr("iconPath");
  if(iP != null)
    filter = filter +";iconPath="+iP;

  var since = "null";
  if(FW_serverGenerated)
    since = FW_serverLastMsg + (FW_serverGenerated-FW_serverFirstMsg);

  var inform = encodeURIComponent("type=status;filter="+filter+
                                  ";since="+since+";fmt=JSON"); // 128651
  var query = "?XHR=1"+
              "&inform="+inform+
              '&fw_id='+$("body").attr('fw_id')+
              "&timestamp="+new Date().getTime();

  var loc = (""+location).replace(/\?.*/,"");
  if(typeof WebSocket == "function" && FW_longpollType == "websocket") {
    FW_pollConn = new WebSocket(loc.replace(/[#&?].*/,'')
                                   .replace(/^http/i, "ws")+query);
    FW_pollConn.onclose = 
    FW_pollConn.onerror = 
    FW_pollConn.onmessage = FW_doUpdate;

  } else {
    FW_pollConn = new XMLHttpRequest();
    FW_pollConn.open("GET", location.pathname+query, true);
    if(FW_pollConn.overrideMimeType)    // Win 8.1, #66004
      FW_pollConn.overrideMimeType("application/json");
    FW_pollConn.onreadystatechange = FW_doUpdate;
    FW_pollConn.send(null);

  }

  log("Inform-channel opened ("+(FW_longpollType==1 ? "HTTP":FW_longpollType)+
                ") with filter "+filter);
}
/*************** LONGPOLL END **************/


/*************** WIDGETS START **************/
/*************** "Double" select in detail window ****/
function
FW_detailSelect(selEl, mayMissing)
{
  if(selEl.target)
    selEl = selEl.target;
  var selVal = $(selEl).val();

  var div = $(selEl).closest("div.makeSelect");
  if(!div.attr("list"))      // hiddenRoom=input
    return;
  var argAndPar, fnd,
      listArr = $(div).attr("list").split(" "),
      devName = $(div).attr("dev"),
      cmd = $(div).attr("cmd");

  if(selVal != null && selVal != undefined) {
    for(var i1=0; i1<listArr.length; i1++) {
      var aap = listArr[i1].split(":");
      try {
        if(selVal.match(new RegExp("^"+aap[0]+"$"))) {
          if(aap.length > 2) {
            var re = aap.shift();
            aap = [re, aap.join(":")];
          }
          argAndPar = aap;
          fnd = true;
        }
      } catch(e){
        log("Problem building regexp from "+listArr[i1]);
      }
    }
  }

  var vArr = [];
  if(!fnd && !mayMissing)
    return;
  if(fnd && argAndPar[1])
    vArr = argAndPar[1].split(",");

  FW_replaceWidget($(selEl).next(), devName, vArr,undefined,selVal,
    undefined, undefined, undefined,
    function(newEl) {
      if(cmd == "attr")
        FW_queryValue('{AttrVal("'+devName+'","'+selVal+'","")}', newEl);
      if(cmd == "set")
        FW_queryValue('{ReadingsVal("'+devName+'","'+selVal+'","")}', newEl);
    });
}

// elName: HTML-Element-id
// devName: FHEM-Device name
// vArr: all parameters split by ,
// current: the value of the current attribute
// set: "cmd" attribute first value
// params: "cmd" attribute other values, split by space
// cmd: function to call, if value changes
function
FW_callCreateFn(elName, devName, vArr, currVal, set, params, cmd, finishFn)
{
  for(var wn in FW_widgets) {
    if(FW_widgets[wn].createFn && !FW_widgets[wn].second) {
      var newEl = FW_widgets[wn].createFn(elName, devName, vArr,
                                          currVal, set, params, cmd);
      if(newEl)
        return finishFn(wn, newEl);
    }
  }

  var v0 = vArr[0].split("-")[0];
  if(v0.indexOf("uzsu") == 0)
    v0 = "uzsu";
  if(FW_availableJs[v0]) {
    loadScript("pgm2/fhemweb_"+v0+".js", function() {
      if(!FW_widgets[vArr[0]]) {
        log("ERROR: fhemweb_"+vArr[v0]+".js does not fill FW_widgets");
        return;
      }
      if(FW_widgets[vArr[0]].createFn)
        var newEl = FW_widgets[vArr[0]].createFn(elName, devName, vArr,
                                                 currVal, set, params, cmd);
      finishFn(vArr[0], newEl);
    });
  } else {
    finishFn();
  }
}

function
FW_replaceWidget(oldEl,devName,vArr,currVal,reading,set,params,cmd,readyFn)
{
  var elName = $(oldEl).attr("name");
  if(!elName)
    elName = $(oldEl).find("[name]").attr("name");

  if(vArr.length == 0) { //  No parameters, input field
    var newEl = FW_createTextField(elName, devName, ["textField"], currVal,
                               set, params, cmd);
    finishFn("textField", newEl);

  } else {
    
    return FW_callCreateFn(elName, devName, vArr, currVal, set,
                           params, cmd, finishFn);

  }

  function
  finishFn(wn, newEl)
  {
    if(!newEl) {
      vArr.unshift("select");
      newEl = FW_createSelect(elName,devName,vArr,currVal,set,params,cmd);
      wn = "select";
    }

    if(!newEl) { // Simple link
      newEl = $('<div class="col3"><a style="cursor: pointer;">'+
                  set+' '+params.join(' ')+ '</a></div>');
      $(newEl).click(function(arg) { cmd(params[0]) });
      $(oldEl).replaceWith(newEl);
      if(readyFn)
        return readyFn(newEl);
      return;
    }

    $(newEl).addClass(wn+"_widget");

    if( $(newEl).find("[informId]").length==0 && !$(newEl).attr("informId") ) {
      if(reading) {
        var a = $(oldEl).closest("form").find("input[type=submit][value=attr]");
        $(newEl).attr("informId", devName+(a.length?"-a-":"-")+reading);
      }
      var addTitle = $("body").attr("data-addHtmlTitle");
      if(reading != "state" && addTitle==1)
        $(newEl).attr("title", reading);
    }
    $(oldEl).replaceWith(newEl);

    if(newEl.activateFn) // CSS is not applied if newEl is not in the document
      newEl.activateFn();
    if(readyFn)
      readyFn(newEl);
  }
}

function
FW_queryValue(cmd, el)
{
  log("FW_queryValue:"+cmd);
  var query = location.pathname+"?cmd="+encodeURIComponent(cmd)+"&XHR=1";
  query = addcsrf(query);
  var qConn = new XMLHttpRequest();
  qConn.onreadystatechange = function() {
    if(qConn.readyState != 4)
      return;
    var qResp = qConn.responseText.replace(/\n$/, '');
    qResp = qResp.replace(/\n/g, '\u2424');
    if(el.setValueFn)
      el.setValueFn(qResp);
    qConn.abort();
  }
  qConn.open("GET", query, true);
  qConn.send(null);
}

/*************** TEXTFIELD **************/
function
FW_createTextField(elName, devName, vArr, currVal, set, params, cmd)
{
  if(vArr.length > 2 ||
     (vArr[0] != "textField" && 
      vArr[0] != "textFieldNL" &&
      vArr[0] != "textField-long" &&
      vArr[0] != "textFieldNL-long") ||
     (params && params.length))
    return undefined;

  var is_long = (vArr[0].indexOf("long") > 0);

  var newEl = $("<div style='display:inline-block'>").get(0);
  if(set && set != "state" && vArr[0].indexOf("NL") < 0)
    $(newEl).append(set+":");
  $(newEl).append('<input type="text" size="30">');
  var inp = $(newEl).find("input").get(0);
  if(elName)
    $(inp).attr('name', elName);
  if(currVal != undefined)
    $(inp).val(currVal);
  if(vArr.length == 2 && !is_long)
    $(inp).attr("placeholder", vArr[1]);

  function addBlur() { if(cmd) $(inp).blur(function() { cmd($(inp).val()) }); };

  newEl.setValueFn = function(arg){ $(inp).val(arg) };
  addBlur();

  var myFunc = function(){
    
    $(inp).unbind("blur");
    $('body').append(
      '<div id="editdlg" style="display:none">'+
        '<textarea id="td_longText" style="width:100%;height:100%;"/>'+
      '</div>');

    var txt = $(inp).val();
    txt = txt.replace(/\u2424/g, '\n');
    $("#td_longText").val(txt);

    var cm;
    if(typeof AddCodeMirror == 'function') {
      AddCodeMirror($("#td_longText"), function(pcm) {cm = pcm;});
    }

    var sz = vArr[1] ? parseInt(vArr[1]) : 75;
    $('#editdlg').dialog(
      { modal:true, closeOnEscape:true, 
        width:$(window).width()*(sz/100),
        height:$(window).height()*(sz/100),
        close:function(){ $('#editdlg').remove(); },
        buttons:[
        { text:"Cancel", click:function(){
          $(this).dialog('close');
          addBlur();
        }},
        { text:"OK", click:function(){
          if(cm)
            $("#td_longText").val(cm.getValue());
          var res=$("#td_longText").val();
          res = res.replace(/\n/g, '\u2424' );
          $(this).dialog('close');
          $(inp).val(res);
          addBlur();
        }}]
      });
  };

  if(is_long)
    $(newEl).click(myFunc);

  return newEl;
}

/*************** select **************/
function
FW_createSelect(elName, devName, vArr, currVal, set, params, cmd)
{
  if(vArr.length < 2 || vArr[0] != "select" || (params && params.length))
    return undefined;
  var newEl = document.createElement('select');
  var vHash = {};
  for(var j=1; j < vArr.length; j++) {
    var o = document.createElement('option');
    if(!vArr[j].match(/&#[0-9a-f]{1,4};/i)) // how to reproduce?
      o.text = o.value = vArr[j].replace(/#/g," ");
    vHash[o.value] = 1;
    newEl.options[j-1] = o;
  }

  if(elName)
    $(newEl).attr('name', elName);
  if(cmd)
    $(newEl).change(function(arg) { cmd($(newEl).val()) });
  newEl.setValueFn = function(arg) {
    if(!vHash[arg] && typeof(arg) != "undefined")
      arg = (arg+"").replace(/ /g,"."); // #124505, replaceAll is Chrome 84+
    if(vHash[arg])
      $(newEl).val(arg);
  };
  newEl.setValueFn(currVal);

  return newEl;
}

/*************** selectNumbers **************/
// Syntax: selectnumbers,<min value>,<step|step of exponent>,<max value>,<number of digits after decimal point>,lin|log10

function
FW_createSelectNumbers(elName, devName, vArr, currVal, set, params, cmd)
{
  if(vArr.length < 6 || vArr[0] != "selectnumbers" || (params && params.length))
    return undefined;

  var min = parseFloat(vArr[1]);
  var stp = parseFloat(vArr[2]);
  var max = parseFloat(vArr[3]);
  var dp  = parseFloat(vArr[4]); // decimal points
  var fun = vArr[5]; // function

  if(currVal != undefined)
    currVal = currVal.replace(/[^\d.\-]/g, "");
  currVal = (currVal==undefined || currVal=="") ?  min : parseFloat(currVal);
  if(max==min)
    return undefined;
  if(!(fun == "lin" || fun == "log10"))
    return undefined;
      
  if(currVal < min) 
    currVal = min;
  if(currVal > max) 
    currVal = max;

  var newEl = document.createElement('select');
  var vHash = {};
  var k = 0;
  var v = 0;
  if (fun == "lin") {
    for(var j=min; j <= max; j+=stp) {
      var o = document.createElement('option');
      o.text = o.value = j.toFixed(dp);
      vHash[o.text] = 1;
      newEl.options[k] = o;
      k++;
    }
  } else if (fun == "log10") {
    if(min <= 0 || max <= 0)
      return undefined;
    for(var j=Math.log10(min); j <= Math.log10(max)+stp; j+=stp) {
      var o = document.createElement('option');
      var w = Math.pow(10, j)
      if (w > max)
        w = max;
      if (v == w.toFixed(dp))
        continue;
      v = w.toFixed(dp);
      o.text = o.value = v;
      vHash[v] = 1;
      newEl.options[k] = o;
      k++;
    }
  }
  if(typeof(currVal) != "undefined")
    $(newEl).val(currVal.toFixed(dp));
  if(elName)
    $(newEl).attr('name', elName);
  if(cmd)
    $(newEl).change(function(arg) { cmd($(newEl).val()) });
  newEl.setValueFn = function(arg) { 
    arg = parseFloat(arg).toFixed(dp);
    if(vHash[arg]) 
      $(newEl).val(arg);
  };
  return newEl;
}

/*************** noArg **************/
function
FW_createNoArg(elName, devName, vArr, currVal, set, params, cmd)
{
  if(vArr.length != 1 || vArr[0] != "noArg" || (params && params.length))
    return undefined;
  var newEl = $('<div style="display:none">').get(0);
  if(elName) 
    $(newEl).append('<input type="hidden" name="'+elName+ '" value="">');
  return(newEl);
}

/*************** slider **************/
function
FW_createSlider(elName, devName, vArr, currVal, set, params, cmd)
{
  // min, step, max, float
  if(vArr.length < 4 || vArr.length > 5 || vArr[0] != "slider" ||
     (params && params.length))
    return undefined;

  var min = parseFloat(vArr[1]);
  var stp = parseFloat(vArr[2]);
  var max = parseFloat(vArr[3]);
  var flt = (vArr.length == 5 && vArr[4] == "1");
  var dp = 0; // decimal points for float
  if(flt) {
    var s = ""+stp;
    if(s.indexOf(".") >= 0)
      dp = s.substr(s.indexOf(".")+1).length;
  }
  if(currVal != undefined)
    currVal = currVal.replace(/[^\d.\-]/g, "");
  currVal = (currVal==undefined || currVal=="") ?  min : parseFloat(currVal);
  if(max==min)
    return undefined;
  if(currVal < min || currVal > max)
    currVal = min;

  var newEl = $('<div style="display:inline-block" tabindex="0">').get(0);
  var slider = $('<div class="slider" id="slider.'+devName+'">').get(0);
  $(newEl).append(slider);

  var sh = $('<div class="handle">'+currVal+'</div>').get(0);
  $(slider).append(sh);
  if(elName)
    $(newEl).append('<input type="hidden" name="'+elName+
                        '" value="'+currVal+'">');

  var lastX=-1, offX=0, maxX=0, val=currVal;

  newEl.activateFn = function() {
    if(currVal < min || currVal > max)
      return;
    if(!slider.offsetWidth)
      return setTimeout(newEl.activateFn, 1);
    maxX = slider.offsetWidth-sh.offsetWidth;
    offX = (currVal-min)*maxX/(max-min);
    var strVal = (flt ? currVal.toFixed(dp) : ""+parseInt(currVal));
    sh.innerHTML = strVal;
    sh.setAttribute('style', 'left:'+offX+'px;');
    if(elName)
      slider.nextSibling.setAttribute('value', strVal);
  }

  $(newEl).keydown(function(e){
         if(e.keyCode == 37) currVal -= stp;
    else if(e.keyCode == 39) currVal += stp;
    else return;

    if(currVal < min) currVal = min;
    if(currVal > max) currVal = max;
    offX = (currVal-min)*maxX/(max-min);
    var strVal = (flt ? currVal.toFixed(dp) : ""+parseInt(currVal));
    sh.innerHTML = strVal;
    sh.setAttribute('style', 'left:'+offX+'px;');
    if(cmd)
      cmd(strVal);
    if(elName)
      slider.nextSibling.setAttribute('value', strVal);
  });

  function
  touchFn(e, fn)
  {
    e.preventDefault(); // Prevents Safari from scrolling!
    if(e.touches == null || e.touches.length == 0)
      return;
    e.clientX = e.touches[0].clientX;
    fn(e);
  }

  function
  mouseDown(e)
  {
    var oldFn1 = document.onmousemove, oldFn2 = document.onmouseup,
        oldFn3 = document.ontouchmove, oldFn4 = document.ontouchend;

    e.stopPropagation();  // Dashboard fix
    lastX = e.clientX;  // Does not work on IE8

    function
    mouseMove(e)
    {
      e.stopPropagation();  // Dashboard fix

      if(maxX == 0) // Forum #35846
        maxX = slider.offsetWidth-sh.offsetWidth;
      var diff = e.clientX-lastX; lastX = e.clientX;
      offX += diff;
      if(offX < 0) offX = 0;
      if(offX > maxX) offX = maxX;
      val = offX/maxX * (max-min);
      val = flt ? (Math.floor(val/stp)*stp+min).toFixed(dp) :
                  (Math.floor(Math.floor(val/stp)*stp)+min);
      sh.innerHTML = val;
      sh.setAttribute('style', 'left:'+offX+'px;');
    }
    document.onmousemove = mouseMove;
    document.ontouchmove = function(e) { touchFn(e, mouseMove); }

    document.onmouseup = document.ontouchend = function(e)
    {
      e.stopPropagation();  // Dashboard fix
      document.onmousemove = oldFn1; document.onmouseup  = oldFn2;
      document.ontouchmove = oldFn3; document.ontouchend = oldFn4;
      if(cmd)
        cmd(val);
      if(elName)
        slider.nextSibling.setAttribute('value', val);
    };
  };

  sh.onselectstart = function() { return false; }
  sh.onmousedown = mouseDown;
  sh.ontouchstart = function(e) { touchFn(e, mouseDown); }

  newEl.setValueFn = function(arg) {
    var res = arg.match(/-?[\d.]+/); // extract first number
    currVal = (res ? parseFloat(res[0]) : min);
    if(currVal < min || currVal > max)
      currVal = min;
    newEl.activateFn();
  };
  return newEl;
}


/*************** TIME **************/
function
FW_createTime(elName, devName, vArr, currVal, set, params, cmd)
{
  if(vArr.length != 1 || vArr[0] != "time" || (params && params.length))
    return undefined;
  var open="-", closed="+";

  var newEl = document.createElement('div');
  $(newEl).append('<input type="text" size="5">');
  $(newEl).append('<input type="button" value="'+closed+'">');

  var inp = $(newEl).find("[type=text]");
  var btn = $(newEl).find("[type=button]");
  currVal = (currVal ? currVal : "12:00")
            .replace(/[^\d]*(\d\d):(\d\d).*/g,"$1:$2");
  $(inp).val(currVal)
  if(elName)
    $(inp).attr("name", elName);

  var hh, mm;   // the slider elements
  newEl.setValueFn = function(arg) {
    arg = arg.replace(/[^\d]*(\d\d):(\d\d).*/g,"$1:$2");
    $(inp).val(arg);
    var hhmm = arg.split(":");
    if(hhmm.length == 2 && hh && mm) {
      hh.setValueFn(hhmm[0]);
      mm.setValueFn(hhmm[1]);
    }
  };

  $(btn).click(function(){      // Open/Close the slider view
    var v = $(inp).val();

    if($(btn).val() == open) {
      $(btn).val(closed);
      $(newEl).find(".timeSlider").remove();
      hh = mm = undefined;
      if(cmd)
        cmd(v);
      return;
    }

    $(btn).val(open);
    if(v.indexOf(":") < 0) {
      v = "12:00";
      $(inp).val(v);
    }
    var hhmm = v.split(":");

    function
    tSet(idx, arg)
    {
      if((""+arg).length < 2)
        arg = '0'+arg;
      hhmm[idx] = arg;
      $(inp).val(hhmm.join(":"));
    }

    $(newEl).append('<div class="timeSlider">');
    var ts = $(newEl).find(".timeSlider");

    hh = FW_createSlider(undefined, devName+"HH", ["slider", 0, 1, 23],
                hhmm[0], undefined, params, function(arg) { tSet(0, arg) });
    mm = FW_createSlider(undefined, devName+"MM", ["slider", 0, 5, 55],
                hhmm[1], undefined, params, function(arg) { tSet(1, arg) });
    $(ts).append("<br>"); $(ts).append(hh); hh.activateFn();
    $(ts).append("<br>"); $(ts).append(mm); mm.activateFn();
  });

  return newEl;
}

/*************** MULTIPLE **************/
function
FW_createMultiple(elName, devName, vArr, currVal, set, params, cmd)
{
  if(vArr.length < 2 || (vArr[0]!="multiple" && vArr[0]!="multiple-strict") ||
     (params && params.length))
    return undefined;
  
  var newEl = $('<input type="text" size="30" readonly>').get(0);
  if(currVal)
    $(newEl).val(currVal);
  if(elName)
    $(newEl).attr("name", elName);
  newEl.setValueFn = function(arg){ $(newEl).val(arg) };

  for(var i1=1; i1<vArr.length; i1++)
    vArr[i1] = vArr[i1].replace(/#/g, " ");

  $(newEl).focus(function(){
    var sel = $(newEl).val().split(","), selObj={};
    for(var i1=0; i1<sel.length; i1++)
      selObj[sel[i1]] = 1;

    var table = "";
    for(var i1=1; i1<vArr.length; i1++) {
      var v = vArr[i1];
      table += '<tr>'+ // funny stuff for ios6 style, forum #23561
        '<td><div class="checkbox">'+
           '<input name="'+v+'" id="multiple_'+v+'" type="checkbox"'+
              (selObj[v] ? " checked" : "")+'/>'+'</div></td>'+
        '<td><label for="multiple_'+v+'">'+v+'</label></td></tr>';
      delete(selObj[v]);
    }

    var selArr=[];
    for(var i1 in selObj)
      selArr.push(i1);
    
    var strict = (vArr[0] == "multiple-strict");
    $('body').append(
      '<div id="multidlg" style="display:none">'+
        '<table>'+table+'</table>'+(!strict ? '<input id="md_freeText" '+
              'value="'+selArr.join(',')+'"/>' : '')+
      '</div>');

    $('#multidlg').dialog(
      { modal:true, closeOnEscape:false, maxHeight:$(window).height()*3/4,
        buttons:[
        { text:"Cancel", click:function(){ $('#multidlg').remove(); }},
        { text:"OK", click:function(){
          var res=[];
          if($("#md_freeText").val())
            res.push($("#md_freeText").val());
          $("#multidlg table input").each(function(){
            if($(this).prop("checked"))
              res.push($(this).attr("name"));
          });
          $('#multidlg').remove();
          $(newEl).val(res.join(","));
          if(cmd)
            cmd(res.join(","));
        }}]});
  });
  return newEl;
}

function
FW_createBitfield(elName, devName, vArr, currVal, set, params, cmd)
{
  if(vArr[0] != "bitfield")
    return undefined;
  if(elName)
    elName = elName.replace(/[^A-Z0-9_]/ig, '_');
  var lName = Math.random().toString(36).substr(2);
  var fieldSize = (vArr.length > 1 ? parseInt(vArr[1]) : 8);
  var bitMask   = (vArr.length > 2 ? parseInt(vArr[2]) : 4294967295);
  var html = '<div style="display:inline-block" tabindex="0">'+
             (elName ? '<input type="hidden" name="'+elName+'">' : '')+
             '<table id="'+lName+'_bitfield">';
  for(var fs=fieldSize; fs>0; ) {
    html += '<tr><td>Bit '+fs+'</td><td>';
    for(var i1=0; i1<8 && fs>0; i1++, fs--)
      html += '<input type="checkbox" value="'+fs+'" title="'+fs+'">';
    html += '</td></tr>\n';
  }
  html += '</table></div>';
  var newEl = $(html).get(0);

  newEl.activateFn = function() {
    var bm = bitMask;
    for(var i1=1; i1<=fieldSize; i1++) {
      $('#'+lName+'_bitfield input[value='+i1+']')
        .prop("disabled", (bm%2 == 0));
      bm = parseInt(bm/2);
    }

    $("#"+lName+"_bitfield input").change(function(){
      var total = 0;
      $("#"+lName+"_bitfield input").each(function(){
        if($(this).is(":checked")) {
          var sv = parseInt($(this).attr("value"))-1, thisVal=1;
          while(sv) { thisVal *= 2; sv--; } // << works on signed 32bit values
          total += thisVal;
        }
      });
      if(cmd)
        cmd(total);
      if(elName)
        $("[name="+elName+"]").val(total);
    });
  }

  newEl.setValueFn = function(arg) {
    var total = parseInt(arg);
    for(var i1=1; i1<=fieldSize; i1++) {
      $('#'+lName+'_bitfield input[value='+i1+']')
        .prop("checked", (total%2 == 1));
      total = parseInt(total/2);
    }
  };
  return newEl;
}

// List of widgets, each one is prepended with its vArr.length
// widgetList,4,select,f1,f2,f3,1,textField,3,select,s1,s2
// No autoloading for subwidgets!
function
FW_createWidgetList(elName, devName, vArr, currVal, set, params, cmd)
{
  if(vArr[0] != "widgetList")
    return undefined;

  var newEl = $('<span><span>').get(0);

  function
  setCmd()
  {
    cmd($(newEl).find("[name^=val]")
                .map( function(){return $(this).val()} )
                .get()
                .join(","));
  }

  if(!elName)
    elName = "val."+Math.random().toString(36).substr(2);
  for(var i1=1; i1<vArr.length; i1++) {
    var lvArr = vArr.slice(i1+1,i1+1+parseInt(vArr[i1]));
    for(var wn in FW_widgets) {
      if(!FW_widgets[wn].createFn || FW_widgets[wn].second)
        continue;
      var subEl = FW_widgets[wn].createFn(elName, devName, lvArr);
      if(subEl) {
        $(newEl).append(subEl);
        if(cmd)
          $(subEl).change(setCmd);
        break;
      }
    }
    i1 += parseInt(vArr[i1]);
  }

  newEl.setValueFn = function(arg) { // , separated values for each widget
    var wa = arg.split(","), idx=0;
    $(newEl).find("[name^=val]").each(function(){
      if(this.setValueFn)
        this.setValueFn(wa[idx++]);
      else
        $(this).val(wa[idx++]);
    });
  };

  return newEl;
}
/*************** WIDGETS END **************/


/*************** SCRIPT LOAD FUNCTIONS START **************/
function
loadScript(sname, callback, force)
{
  var h = document.head || document.getElementsByTagName('head')[0];
  sname = FW_root+"/"+sname;
  if(FW_scripts[sname]) {
    if(FW_scripts[sname].loaded) {
      if(callback)
        callback();
    } else {
      FW_scripts[sname].callbacks.push(callback);
    }
    return;
  }
  if(!FW_docReady && !force) {
    FW_scripts[sname] = { callbacks:[ callback] };
    return;
  }

  var script = document.createElement("script");
  script.src = sname;
  script.async = script.defer = false;
  script.type = "text/javascript";
  FW_scripts[sname] = { callbacks:[ callback] };

  function
  scriptLoaded()
  {
    var p = FW_scripts[sname];
    p.loaded = true;
    if(!p.called) {
      p.called = true;
      for(var i1=0; i1< p.callbacks.length; i1++)
        if(p.callbacks[i1]) // pushing undefined callbacks on the stack is ok
          p.callbacks[i1]();
    }
    delete(p.callbacks);
  }

  log("Loading script "+sname);
  if(FW_isIE) {
    script.onreadystatechange = function() {
      if(script.readyState == 'loaded' || script.readyState == 'complete') {
        script.onreadystatechange = null;
        scriptLoaded();
      }
    }

  } else {
    if(FW_isiOS)
     FW_closeConn();
    script.onload = function(){
      scriptLoaded();
    }
  }
  h.appendChild(script);
}

function
loadLink(lname)
{
  var h = document.head || document.getElementsByTagName('head')[0];
  lname = FW_root+"/"+lname;

  var arr = h.getElementsByTagName("link");
  for(var i1=0; i1<arr.length; i1++)
    if(lname == arr[i1].getAttribute("href"))
      return;
  var link = document.createElement("link");
  link.href = lname;
  link.rel = "stylesheet";
  log("Loading link "+lname);
  h.appendChild(link);
}

function
scriptAttribute(sname)
{
  var attr="";
  $("head script").each(function(){
    var src = $(this).attr("src");
    if(src && src.indexOf(sname) >= 0)
      attr = $(this).attr("attr");
  });

  var ua={};
  if(attr && attr != "") {
    try {
      ua=JSON.parse(attr);
    } catch(e){
      FW_errmsg(sname+" Parameter "+e,5000);
    }
  }
  return ua;
}
/*************** SCRIPT LOAD FUNCTIONS END **************/

function
print_call_stack() {
  var stack = new Error().stack;
  console.log("PRINTING CALL STACK");
  console.log( stack );
}

function
FW_getSVG(emb)
{
  if(emb.contentDocument)
    return emb.contentDocument;
  if(typeof emb.getSVGDocument == "function") {
    try {
      return emb.getSVGDocument();
    } catch(err) {
      // dom not loaded -> fall through -> retry;
    }
  }
  return undefined;
}

function
FW_checkNotifydev(reName)
{
  var internals={};
  $("table.internals tr td div.dname").each(function(){
    internals[$(this).html()] = this;
  });
  if(!internals[reName] || internals.NOTIFYDEV)
    return;
  $(internals[reName])
    .html(reName+" <a>(!)</a>")
    .css("cursor","pointer")
    .click(function(){
      var val = $(internals[reName]).closest("tr").find("div[informid]").text();
      FW_okDialog("Could not optimize the regexp:<ul>"+val+
                "</ul>How I tried (notifyRegexpCheck):<ul><pre></pre></ul>");
      FW_cmd(FW_root+'?cmd={notifyRegexpCheck("'+val+'")}&XHR=1',
      function(res){
        $("#FW_okDialog pre").html(res);
      });

    });
}

function
FW_rescueClient(pid, key)
{
  var html='<div id="rescueDialog" style="display:none">';
  if(!pid || pid == "0") {
    html += '<b>Key (send it to the rescuer):</b><br>'+
            (key ? '<code>'+key+'</code>' : 'Not found, generate one first');
    html += '<br><br>';
  }

  var buttons = [];

  if(key) {
    if(pid && pid != "0") {
      html += "<div>There is a connection with pid "+pid+"</div><br>";
      buttons.push({
        text:"Terminate connection",
        click:function(){
          FW_cmd(FW_root+
            "?cmd=set "+$("body").attr("data-webname")+
            " rescueTerminate&XHR=1");
          setTimeout(function(){ location.reload() }, 1000);
        }});

    } else {
      html += "Address (rescuer will tell you host and port)<br>";
      html += "<input type='text' size='20' placeholder='host port' >";

      buttons.push({
        text:"Start connection",
        click:function(){
          FW_cmd(FW_root+
            "?cmd=set "+$("body").attr("data-webname")+" rescueStart "+
            $("#rescueDialog input").val()+"&XHR=1");
          setTimeout(function(){ location.reload() }, 1000);
        }});
    }
  }

  buttons.push({ text:"Cancel", click:function(){ $(this).dialog('close')} });

  $('body').append(html);

  $('#rescueDialog').dialog({
    modal:true, closeOnEscape:true, width:"auto",
    close:function(){ $('#rescueDialog').remove(); },
    buttons:buttons
  });
}

/*
=pod

=begin html

  <li>noArg - show no input field.</li>
  <li>time - show a JavaScript driven timepicker.<br>
      Example: attr FS20dev widgetOverride on-till:time</li>
  <li>textField[,placeholder] - show an input field.<br>
      Example: attr WEB widgetOverride room:textField</li>
  <li>textFieldNL[,placeholder] - show the input field and hide the label.</li>
  <li>textField-long[,sizePct] - show an input-field, but upon
      clicking on the input field open a textArea.
      sizePct specifies the size of the dialog relative to the screen, in
      percent. Default is 75</li>
  <li>textFieldNL-long[,sizePct] - the behaviour is the same
      as :textField-long, but no label is displayed.</li>
  <li>slider,&lt;min&gt;,&lt;step&gt;,&lt;max&gt;[,1] - show
      a JavaScript driven slider. The optional ,1 at the end
      avoids the rounding of floating-point numbers.</li>
  <li>multiple,&lt;val1&gt;,&lt;val2&gt;,..." - present a
      multiple-value-selector with an additional textfield. The result is
      comman separated.</li>
  <li>multiple-strict,&lt;val1&gt;,&lt;val2&gt;,... - like :multiple, but
      without the textfield.</li>
  <li>selectnumbers,&lt;min&gt;,&lt;step&gt;,&lt;max&gt;,&lt;number of
      digits after decimal point&gt;,lin|log10" - display a select widget
      generated with values from min to max with step.<br>
      lin generates a constantly increasing series.  log10 generates an
      exponentially increasing series to base 10, step is related to the
      exponent, e.g. 0.0625.</li>
  <li>select,&lt;val1&gt;,&lt;val2&gt;,... - show a dropdown with all values.
      <b>NOTE</b>: this is also the fallback, if no modifier is found.</li>
  <li>bitfield,&lt;size&gt;&lt;mask&gt; - show a table of checkboxes (8 per
      line) to set single bits. Default for size is 8 and for mask 2^32-1</li>
  <li>widgetList,... - show a list of widgets. The arguments are concatenated,
      and separated be the length of the following argument list.<br>
      Example: widgetList,3,select,opt1,opt2,1,textField<br>
      Note: the values will be sent to FHEM as a comma separated list, and only
      preloaded widgets can be referenced.</li>

=end html

=begin html_DE

  <li>noArg - es wird kein weiteres Eingabefeld angezeigt.</li>
  <li>time - zeigt ein Zeitauswahlmen&uuml;.
      Beispiel: attr FS20dev widgetOverride on-till:time</li>
  <li>textField[,placeholder] - zeigt ein Eingabefeld.<br>
      Beispiel: attr WEB widgetOverride room:textField</li>
  <li>textFieldNL[,placeholder] - Eingabefeld ohne Label.</li>
  <li>textField-long[,sizePct] - ist wie textField, aber beim Click im
      Eingabefeld wird ein Dialog mit einer HTML textarea wird
      ge&ouml;ffnet.  sizePct ist die relative Gr&ouml;&szlig;e des Dialogs,
      die Voreinstellung ist 75.</li>
  <li>textFieldNL-long[,sizePct] - wi textField-long, aber kein Label wir
      angezeigt.</li>
  <li>slider,&lt;min&gt;,&lt;step&gt;,&lt;max&gt;[,1] - zeigt einen
      Schieberegler. Das optionale 1 (isFloat) vermeidet eine Rundung der
      Fliesskommazahlen.</li>
  <li>multiple,&lt;val1&gt;,&lt;val2&gt;,... - zeigt eine Mehrfachauswahl mit
      einem zus&auml;tzlichen Eingabefeld. Das Ergebnis ist Komma
      separiert.</li>
  <li>multiple-strict,&lt;val1&gt;,&lt;val2&gt;,... - ist wie :multiple,
      blo&szlig; ohne Eingabefeld.</li>
  <li>selectnumbers,&lt;min&gt;,&lt;step&gt;,&lt;max&gt;,&lt;number of
      digits after decimal point&gt;,lin|log10" zeigt ein HTML-select mit einer
      Zahlenreihe vom Wert min bis Wert max mit Schritten von step
      angezeigt.<br>
      Die Angabe lin erzeugt eine konstant ansteigende Reihe.  Die Angabe
      log10 erzeugt eine exponentiell ansteigende Reihe zur Basis 10,
      step bezieht sich auf den Exponenten, z.B. 0.0625.</li>
  <li>select,&lt;val1&gt;,&lt;val2&gt;,... - zeigt ein HTML select mit allen
      Werten. <b>Achtung</b>: so ein Widget wird auch dann angezeigt, falls
      kein passender Modifier gefunden wurde.</li>
  <li>bitfield,&lt;size&gt;,&lt;mask&gt; - zeigt eine Tabelle von
      Kontrollk&auml;stchen (8 pro Zeile), um einzelne Bits setzen zu koennen.
      Die Voreinstellung fuer size ist 8 und fuer mask 2^32-1.</li>
  <li>widgetList,... - zeigt eine Liste von Widgets. Die Argumente aller
      widgets sind durch die L&auml;ngenangabe der jeweiligen Argumentliste
      getrennt.<br>
      Beispiel: widgetList,3,select,opt1,opt2,1,textField<br>
      Achtung: die Werte werden Komma separiert zu FHEM gesendet, und es
      k&ouml;nnen nur bereits geladene widgets definiert werden.</li>

=end html_DE

=cut
*/
